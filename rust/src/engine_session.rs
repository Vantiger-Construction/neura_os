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
    sync::{Arc, Mutex},
    thread::{self, JoinHandle},
    time::Duration,
};
use tokio::sync::{oneshot, watch};
use tokio_tungstenite::tungstenite::{
    client::IntoClientRequest, http::HeaderValue, protocol::WebSocketConfig, Message,
};
use zeroize::Zeroizing;

pub(crate) const DISABLED: i32 = 0;
pub(crate) const STARTING: i32 = 1;
pub(crate) const IDLE: i32 = 2;
pub(crate) const ERROR: i32 = 3;
pub(crate) const UNAVAILABLE: i32 = 4;
pub(crate) const BLOCKED: i32 = 5;
pub(crate) const WORKING: i32 = 6;
pub(crate) const PAUSED: i32 = 7;
const START_TIMEOUT: Duration = Duration::from_secs(3);
const PROBE_TIMEOUT: Duration = Duration::from_secs(3);
const MAX_FIXTURE_FRAMES: usize = 16;
const REVOKE_TIMEOUT: Duration = Duration::from_millis(250);

struct Snapshot {
    generation: u64,
    status: i32,
}

// Check generation and publish under the same lock. A cancelled completion or
// error cannot overwrite Pause, Stop, a safety block, or a replacement session.
pub(crate) struct RuntimeState(Mutex<Snapshot>);

impl RuntimeState {
    pub(crate) fn new() -> Self {
        Self(Mutex::new(Snapshot {
            generation: 0,
            status: DISABLED,
        }))
    }

    pub(crate) fn status(&self) -> i32 {
        self.0
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .status
    }

    pub(crate) fn invalidate(&self, status: i32) -> u64 {
        let mut snapshot = self.0.lock().unwrap_or_else(|poison| poison.into_inner());
        snapshot.generation = snapshot.generation.wrapping_add(1);
        snapshot.status = status;
        snapshot.generation
    }

    pub(crate) fn publish(&self, generation: u64, status: i32) -> bool {
        let mut snapshot = self.0.lock().unwrap_or_else(|poison| poison.into_inner());
        if snapshot.generation != generation {
            return false;
        }
        snapshot.status = status;
        true
    }

    pub(crate) fn exhaust(&self, generation: u64) {
        let mut snapshot = self.0.lock().unwrap_or_else(|poison| poison.into_inner());
        if snapshot.generation == generation {
            snapshot.generation = snapshot.generation.wrapping_add(1);
            snapshot.status = PAUSED;
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum ProbeFailure {
    Failed,
    Exhausted,
}

impl From<tokio_tungstenite::tungstenite::Error> for ProbeFailure {
    fn from(error: tokio_tungstenite::tungstenite::Error) -> Self {
        match error {
            tokio_tungstenite::tungstenite::Error::Capacity(_) => Self::Exhausted,
            _ => Self::Failed,
        }
    }
}

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
    state: Arc<RuntimeState>,
    active: Option<Active>,
}

impl Launcher {
    pub(crate) fn new(executable: Option<PathBuf>) -> Self {
        Self {
            executable,
            foreground: false,
            blocked: false,
            state: Arc::new(RuntimeState::new()),
            active: None,
        }
    }

    pub(crate) fn status(&self) -> i32 {
        self.state.status()
    }

    pub(crate) fn start(&mut self) -> i32 {
        if self.blocked || !self.foreground {
            return BLOCKED;
        }
        // Pause is a separate permission boundary; Start cannot bypass it.
        if self.status() == PAUSED {
            return PAUSED;
        }
        self.launch()
    }

    pub(crate) fn resume(&mut self) -> i32 {
        if self.blocked || !self.foreground {
            return BLOCKED;
        }
        if self.status() != PAUSED {
            return self.status();
        }
        // Budget exhaustion can publish Paused just before teardown finishes.
        // Join that owner before creating a new generation or credential.
        self.end(PAUSED);
        self.launch()
    }

    fn launch(&mut self) -> i32 {
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
        let generation = self.state.invalidate(STARTING);
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
                                generation,
                            ))
                        },
                    )
                }));
                // Cancellation invalidates every result before Stop returns. Joining
                // the old owner before restart prevents an earlier generation from
                // publishing into a replacement session.
                if !*receiver.borrow() && !matches!(result, Ok(Ok(_))) {
                    state.publish(generation, ERROR);
                }
            });
        match worker {
            Ok(worker) => self.active = Some(Active { cancel, worker }),
            Err(_) => {
                self.state.publish(generation, ERROR);
            }
        }
        self.status()
    }

    pub(crate) fn stop(&mut self) {
        self.end(if self.blocked { BLOCKED } else { DISABLED });
    }

    pub(crate) fn pause(&mut self) -> i32 {
        if matches!(self.status(), STARTING | WORKING | IDLE | PAUSED) && !self.blocked {
            self.end(PAUSED);
        }
        self.status()
    }

    fn end(&mut self, status: i32) {
        // Invalidate first, including before an in-flight response can publish.
        self.state.invalidate(status);
        if let Some(session) = self.active.take() {
            session.cancel.send_replace(true);
            // The worker cancels network awaits, attempts bounded revocation,
            // kills/reaps its owned process, closes the pipe and wipes secrets.
            let _ = session.worker.join();
        }
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
    state: Arc<RuntimeState>,
    generation: u64,
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
        result = tokio::time::timeout(START_TIMEOUT, ready_rx) => match result {
            Ok(result) => result.map_err(|_| ())??,
            Err(_) => { state.exhaust(generation); return Ok(None); }
        },
    };
    if !owner.child.is_running() {
        return Err(());
    }
    if !state.publish(generation, WORKING) {
        let revoked = revoke(address, &token).await.is_ok();
        return Ok(Some((address, revoked)));
    }
    let probe = tokio::select! {
        biased;
        _ = cancelled(&mut cancel) => None,
        result = bounded_probe(address, &token, &state, generation) => Some(result),
    };
    if probe == Some(Ok(())) && !*cancel.borrow() && !owner.child.is_running() {
        return Err(());
    }
    if probe == Some(Ok(()))
        && !*cancel.borrow()
        && owner.child.is_running()
        && state.publish(generation, IDLE)
    {
        loop {
            tokio::select! {
                biased;
                _ = cancelled(&mut cancel) => break,
                _ = tokio::time::sleep(Duration::from_secs(1)) => {
                    if !owner.child.is_running() { return Err(()); }
                }
            }
        }
    }
    // Even failed diagnostics must end the authenticated session. Do not
    // redirect, use proxies, flush queued output, or retry a stopped session.
    let revoked = owner.child.is_running() && revoke(address, &token).await.is_ok();
    if probe == Some(Err(ProbeFailure::Failed)) {
        Err(())
    } else {
        Ok(Some((address, revoked)))
    }
}

pub(crate) async fn bounded_probe(
    address: SocketAddr,
    token: &str,
    state: &RuntimeState,
    generation: u64,
) -> Result<(), ProbeFailure> {
    let result = tokio::time::timeout(PROBE_TIMEOUT, probe(address, token))
        .await
        .unwrap_or(Err(ProbeFailure::Exhausted));
    if result == Err(ProbeFailure::Exhausted) {
        state.exhaust(generation);
    }
    result
}

async fn probe(address: SocketAddr, token: &str) -> Result<(), ProbeFailure> {
    let mut request = format!("ws://{address}/")
        .into_client_request()
        .map_err(|_| ProbeFailure::Failed)?;
    let mut authorization =
        HeaderValue::from_str(&format!("Bearer {token}")).map_err(|_| ProbeFailure::Failed)?;
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
        .map_err(ProbeFailure::from)?;
    // These are the entire client protocol. No user text, room, model, memory,
    // voice, action, source or reflection arguments can enter this path.
    for (kind, expected) in [("hello", "hello"), ("diagnostics_request", "diagnostics")] {
        socket
            .send(Message::Text(
                json!({"v":1,"kind":kind,"data":{}}).to_string(),
            ))
            .await
            .map_err(ProbeFailure::from)?;
        let frame = socket
            .next()
            .await
            .ok_or(ProbeFailure::Failed)?
            .map_err(ProbeFailure::from)?;
        let Message::Text(text) = frame else {
            return Err(ProbeFailure::Failed);
        };
        let value: Value = serde_json::from_str(&text).map_err(|_| ProbeFailure::Failed)?;
        if value["v"] != 1
            || value["kind"] != expected
            || value["data"]["input_scope"] != "synthetic-only"
        {
            return Err(ProbeFailure::Failed);
        }
        if kind == "diagnostics_request"
            && !value["data"]["checks"]
                .as_array()
                .ok_or(ProbeFailure::Failed)?
                .iter()
                .any(|check| check["name"] == "Model adapter" && check["status"] == "degraded")
        {
            return Err(ProbeFailure::Failed);
        }
        // Release the control reply before reading fixture frames; the bounded
        // client retains at most one decoded response at a time.
        drop(value);
        drop(text);
        if kind == "hello" {
            socket
                .send(Message::Text(
                    json!({"v":1,"kind":"synthetic_input","data":{"fixture":"hello"}}).to_string(),
                ))
                .await
                .map_err(ProbeFailure::from)?;
            let mut completed = false;
            // The fixed hello has eight deltas and one completion. Neither
            // chunks nor diagnostics text is delivered to Flutter or retained.
            for _ in 0..MAX_FIXTURE_FRAMES {
                let frame = socket
                    .next()
                    .await
                    .ok_or(ProbeFailure::Failed)?
                    .map_err(ProbeFailure::from)?;
                let Message::Text(text) = frame else {
                    return Err(ProbeFailure::Failed);
                };
                let value: Value = serde_json::from_str(&text).map_err(|_| ProbeFailure::Failed)?;
                if value["v"] != 1 {
                    return Err(ProbeFailure::Failed);
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
                    _ => return Err(ProbeFailure::Failed),
                }
            }
            if !completed {
                return Err(ProbeFailure::Exhausted);
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
pub extern "C" fn neura_engine_pause_synthetic() -> i32 {
    native_launcher()
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .pause()
}
#[no_mangle]
pub extern "C" fn neura_engine_resume_synthetic() -> i32 {
    native_launcher()
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .resume()
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
