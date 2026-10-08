//! Native-owned Windows synthetic session. No credential or arbitrary input
//! crosses the C ABI; the library is idle until the visible Console starts it.

#[path = "engine_process.rs"]
pub(crate) mod process;

use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::{
    io::Read,
    net::SocketAddr,
    path::PathBuf,
    sync::{
        atomic::{AtomicI32, Ordering},
        Arc, Mutex,
    },
    thread::{self, JoinHandle},
    time::Duration,
};
use tokio::sync::{oneshot, watch};
use tokio_tungstenite::tungstenite::{
    client::IntoClientRequest, http::HeaderValue, protocol::WebSocketConfig, Message,
};
use zeroize::Zeroizing;

pub(crate) const STOPPED: i32 = 0;
pub(crate) const STARTING: i32 = 1;
pub(crate) const READY: i32 = 2;
pub(crate) const ERROR: i32 = 3;
pub(crate) const UNAVAILABLE: i32 = 4;
pub(crate) const BLOCKED: i32 = 5;
const START_TIMEOUT: Duration = Duration::from_secs(3);
const REVOKE_TIMEOUT: Duration = Duration::from_millis(250);

// Keep this holder out of Debug, error payloads and diagnostics.
pub(crate) fn fresh_token() -> Result<Zeroizing<String>, ()> {
    let mut bytes = Zeroizing::new([0u8; 32]);
    getrandom::getrandom(bytes.as_mut()).map_err(|_| ())?;
    let mut token = Zeroizing::new(String::with_capacity(64));
    use std::fmt::Write;
    for byte in bytes.iter() {
        write!(token, "{byte:02x}").map_err(|_| ())?;
    }
    Ok(token)
}

struct Active {
    cancel: watch::Sender<bool>,
    worker: JoinHandle<()>,
}

pub(crate) struct Launcher {
    executable: Option<PathBuf>,
    foreground: bool,
    blocked: bool,
    state: Arc<AtomicI32>,
    active: Option<Active>,
}

impl Launcher {
    pub(crate) fn new(executable: Option<PathBuf>) -> Self {
        Self {
            executable,
            foreground: false,
            blocked: false,
            state: Arc::new(AtomicI32::new(STOPPED)),
            active: None,
        }
    }

    pub(crate) fn status(&self) -> i32 {
        self.state.load(Ordering::SeqCst)
    }

    pub(crate) fn start(&mut self) -> i32 {
        if self.blocked || !self.foreground {
            return BLOCKED;
        }
        let Some(executable) = self.executable.clone() else {
            return UNAVAILABLE;
        };
        if self
            .active
            .as_ref()
            .is_some_and(|session| !session.worker.is_finished())
        {
            return self.status();
        }
        self.stop();
        let (cancel, receiver) = watch::channel(false);
        let state = self.state.clone();
        self.state.store(STARTING, Ordering::SeqCst);
        let worker = thread::Builder::new()
            .name("neura-synthetic-ipc".into())
            .spawn(move || {
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    let runtime = tokio::runtime::Builder::new_current_thread()
                        .enable_all()
                        .build()
                        .map_err(|_| ())?;
                    // Other native library users may enable dependency tracing.
                    // This dedicated thread never emits HTTP headers/wire bytes.
                    tracing::subscriber::with_default(
                        tracing::subscriber::NoSubscriber::default(),
                        || {
                            runtime.block_on(run_session(
                                executable,
                                receiver.clone(),
                                state.clone(),
                            ))
                        },
                    )
                }));
                // Cancellation invalidates every result before Stop returns. Joining
                // the old owner before restart prevents an earlier generation from
                // publishing into a replacement session.
                if !*receiver.borrow() && !matches!(result, Ok(Ok(_))) {
                    state.store(ERROR, Ordering::SeqCst);
                }
            });
        match worker {
            Ok(worker) => self.active = Some(Active { cancel, worker }),
            Err(_) => self.state.store(ERROR, Ordering::SeqCst),
        }
        self.status()
    }

    pub(crate) fn stop(&mut self) {
        if let Some(session) = self.active.take() {
            session.cancel.send_replace(true);
            self.state.store(STOPPED, Ordering::SeqCst);
            // The worker cancels network awaits, attempts bounded revocation,
            // kills/reaps its owned process, closes the pipe and wipes secrets.
            let _ = session.worker.join();
        }
        self.state.store(
            if self.blocked { BLOCKED } else { STOPPED },
            Ordering::SeqCst,
        );
    }

    pub(crate) fn set_foreground(&mut self, foreground: bool) {
        self.foreground = foreground;
        if !foreground {
            self.stop();
        }
    }

    pub(crate) fn block(&mut self) {
        self.blocked = true;
        self.stop();
    }
}

impl Drop for Launcher {
    fn drop(&mut self) {
        self.stop();
    }
}

async fn cancelled(cancel: &mut watch::Receiver<bool>) {
    if !*cancel.borrow_and_update() {
        let _ = cancel.changed().await;
    }
}

// Bounded receipt from the child's inherited stdout, never a URL supplied by
// Flutter, an environment override, a log parser or a guessed/reserved port.
pub(crate) fn read_ready(mut pipe: impl Read) -> Result<SocketAddr, ()> {
    let mut line = Vec::with_capacity(80);
    for _ in 0..80 {
        let mut byte = [0];
        pipe.read_exact(&mut byte).map_err(|_| ())?;
        if byte[0] == b'\n' {
            let line = std::str::from_utf8(&line).map_err(|_| ())?;
            let address: SocketAddr = line
                .strip_prefix("NEURA_IPC_READY ")
                .ok_or(())?
                .parse()
                .map_err(|_| ())?;
            return if address.ip() == std::net::Ipv4Addr::LOCALHOST && address.port() != 0 {
                Ok(address)
            } else {
                Err(())
            };
        }
        line.push(byte[0]);
    }
    Err(())
}

// Own the reader as well as the child. Killing the job first closes all child
// pipe writers, so cancellation/timeout cannot leave a detached reader thread.
struct SessionOwner {
    child: process::ChildProcess,
    reader: Option<JoinHandle<()>>,
}
impl Drop for SessionOwner {
    fn drop(&mut self) {
        self.child.terminate();
        if let Some(reader) = self.reader.take() {
            let _ = reader.join();
        }
    }
}

pub(crate) async fn run_session(
    executable: PathBuf,
    mut cancel: watch::Receiver<bool>,
    state: Arc<AtomicI32>,
) -> Result<Option<(SocketAddr, bool)>, ()> {
    if *cancel.borrow() {
        return Ok(None);
    }
    let token = fresh_token()?;
    let (child, pipe) = process::spawn(&executable, &token)?;
    let mut owner = SessionOwner {
        child,
        reader: None,
    };
    let (ready_tx, ready_rx) = oneshot::channel();
    owner.reader = Some(
        thread::Builder::new()
            .name("neura-ipc-ready".into())
            .spawn(move || {
                let _ = ready_tx.send(read_ready(pipe));
            })
            .map_err(|_| ())?,
    );
    let address = tokio::select! {
        biased;
        _ = cancelled(&mut cancel) => return Ok(None),
        result = tokio::time::timeout(START_TIMEOUT, ready_rx) => result.map_err(|_| ())?.map_err(|_| ())??,
    };
    if !owner.child.is_running() {
        return Err(());
    }
    let probe = tokio::select! {
        biased;
        _ = cancelled(&mut cancel) => Ok(()),
        result = tokio::time::timeout(START_TIMEOUT, probe(address, &token)) => result.unwrap_or(Err(())),
    };
    if probe.is_ok() && !*cancel.borrow() && owner.child.is_running() {
        state.store(READY, Ordering::SeqCst);
        loop {
            tokio::select! {
                biased;
                _ = cancelled(&mut cancel) => break,
                _ = tokio::time::sleep(Duration::from_millis(100)) => {
                    if !owner.child.is_running() { return Err(()); }
                }
            }
        }
    }
    // Even failed diagnostics must end the authenticated session. Do not
    // redirect, use proxies, flush queued output, or retry a stopped session.
    let revoked = owner.child.is_running() && revoke(address, &token).await.is_ok();
    probe.map(|_| Some((address, revoked)))
}

async fn probe(address: SocketAddr, token: &str) -> Result<(), ()> {
    let mut request = format!("ws://{address}/")
        .into_client_request()
        .map_err(|_| ())?;
    let mut authorization = HeaderValue::from_str(&format!("Bearer {token}")).map_err(|_| ())?;
    authorization.set_sensitive(true);
    request.headers_mut().insert("Authorization", authorization);
    let config = WebSocketConfig {
        write_buffer_size: 0,
        max_write_buffer_size: 8192,
        max_message_size: Some(4096),
        max_frame_size: Some(4096),
        ..Default::default()
    };
    let (mut socket, _) = tokio_tungstenite::connect_async_with_config(request, Some(config), true)
        .await
        .map_err(|_| ())?;
    // These are the entire client protocol. No user text, room, model, memory,
    // voice, action, source or reflection arguments can enter this path.
    for (kind, expected) in [("hello", "hello"), ("diagnostics_request", "diagnostics")] {
        socket
            .send(Message::Text(
                json!({"v":1,"kind":kind,"data":{}}).to_string(),
            ))
            .await
            .map_err(|_| ())?;
        let frame = socket.next().await.ok_or(())?.map_err(|_| ())?;
        let Message::Text(text) = frame else {
            return Err(());
        };
        let value: Value = serde_json::from_str(&text).map_err(|_| ())?;
        if value["v"] != 1
            || value["kind"] != expected
            || value["data"]["input_scope"] != "synthetic-only"
        {
            return Err(());
        }
        if kind == "diagnostics_request"
            && !value["data"]["checks"]
                .as_array()
                .ok_or(())?
                .iter()
                .any(|check| check["name"] == "Model adapter" && check["status"] == "degraded")
        {
            return Err(());
        }
        if kind == "hello" {
            socket
                .send(Message::Text(
                    json!({"v":1,"kind":"synthetic_input","data":{"fixture":"hello"}}).to_string(),
                ))
                .await
                .map_err(|_| ())?;
            let mut completed = false;
            // The fixed hello has eight deltas and one completion. Neither
            // chunks nor diagnostics text is delivered to Flutter or retained.
            for _ in 0..16 {
                let frame = socket.next().await.ok_or(())?.map_err(|_| ())?;
                let Message::Text(text) = frame else {
                    return Err(());
                };
                let value: Value = serde_json::from_str(&text).map_err(|_| ())?;
                if value["v"] != 1 {
                    return Err(());
                }
                match value["kind"].as_str() {
                    Some("speak_delta") => {}
                    Some("speak")
                        if value["data"]["text"]
                            == "Local brain link is working. Synthetic input." =>
                    {
                        completed = true;
                        break;
                    }
                    _ => return Err(()),
                }
            }
            if !completed {
                return Err(());
            }
        }
    }
    // Drop the socket after the one bounded probe, retaining no response data.
    Ok(())
}

pub(crate) async fn revoke(address: SocketAddr, token: &str) -> Result<(), ()> {
    let client = reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(REVOKE_TIMEOUT)
        .build()
        .map_err(|_| ())?;
    let response = client
        .post(format!("http://{address}/session/revoke"))
        .bearer_auth(token)
        .send()
        .await
        .map_err(|_| ())?;
    if response.status() == reqwest::StatusCode::NO_CONTENT {
        Ok(())
    } else {
        Err(())
    }
}

fn native_launcher() -> &'static Mutex<Launcher> {
    static LAUNCHER: std::sync::OnceLock<Mutex<Launcher>> = std::sync::OnceLock::new();
    LAUNCHER.get_or_init(|| {
        Mutex::new(Launcher::new(if cfg!(windows) {
            std::env::current_exe()
                .ok()
                .and_then(|path| path.parent().map(|parent| parent.join("neura_api.exe")))
        } else {
            None
        }))
    })
}

#[no_mangle]
pub extern "C" fn neura_engine_start_synthetic() -> i32 {
    native_launcher()
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .start()
}
#[no_mangle]
pub extern "C" fn neura_engine_synthetic_status() -> i32 {
    native_launcher()
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .status()
}
#[no_mangle]
pub extern "C" fn neura_engine_stop_synthetic() {
    native_launcher()
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .stop();
}
#[no_mangle]
pub extern "C" fn neura_engine_synthetic_foreground(foreground: i32) {
    native_launcher()
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .set_foreground(foreground == 1);
}
#[no_mangle]
pub extern "C" fn neura_engine_block_synthetic() {
    native_launcher()
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .block();
}
