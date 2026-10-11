//! Native-owned, opt-in typed text. No sources, speech, actions or cloud routing.
use crate::engine_session::{
    fresh_token, process, read_ready, BLOCKED, DISABLED, ERROR, IDLE, STARTING, UNAVAILABLE,
    WORKING,
};
use crate::local_conversation::{LocalConversation, LocalTextGrant, MAX_INPUT_BYTES};
use std::{
    path::PathBuf,
    sync::{Arc, Mutex, OnceLock},
    thread::{self, JoinHandle},
    time::Duration,
};
use tokio::sync::{mpsc, oneshot, watch};
use zeroize::Zeroizing;

const START_TIMEOUT: Duration = Duration::from_secs(180);
const MAX_REPLY_BYTES: usize = 4096;

struct Snapshot {
    epoch: u64,
    status: i32,
    reply: Option<Zeroizing<String>>,
}
struct State(Mutex<Snapshot>);
impl State {
    fn new() -> Self {
        Self(Mutex::new(Snapshot {
            epoch: 0,
            status: DISABLED,
            reply: None,
        }))
    }
    fn invalidate(&self, status: i32) -> u64 {
        let mut s = self.0.lock().unwrap_or_else(|p| p.into_inner());
        s.epoch = s.epoch.wrapping_add(1);
        s.status = status;
        s.reply = None;
        s.epoch
    }
    fn publish(&self, epoch: u64, status: i32, reply: Option<Zeroizing<String>>) -> bool {
        let mut s = self.0.lock().unwrap_or_else(|p| p.into_inner());
        if s.epoch != epoch {
            return false;
        }
        s.status = status;
        s.reply = reply;
        true
    }
    fn status(&self) -> i32 {
        self.0.lock().unwrap_or_else(|p| p.into_inner()).status
    }
}

struct Configuration {
    powershell: PathBuf,
    script: PathBuf,
    assets: PathBuf,
    window: usize,
}
impl Configuration {
    fn plan(&self, token: &str, temporary: &std::path::Path) -> process::SpawnSpec {
        process::SpawnSpec {
            executable: self.powershell.clone(),
            arguments: vec![
                "-NoLogo".into(),
                "-NoProfile".into(),
                "-NonInteractive".into(),
                "-File".into(),
                self.script.to_string_lossy().into_owned(),
                "-NativeOwner".into(),
                "-AllowSessionText".into(),
            ],
            environment: vec![
                ("NEURA_LOCAL_SESSION_TOKEN".into(), token.into()),
                ("NEURA_LOCAL_APP_WINDOW".into(), self.window.to_string()),
                (
                    "NEURA_LOCAL_ASSETS_ROOT".into(),
                    self.assets.to_string_lossy().into_owned(),
                ),
                (
                    "NEURA_LOCAL_RUNTIME_ROOT".into(),
                    temporary.to_string_lossy().into_owned(),
                ),
                ("OS".into(), "Windows_NT".into()),
                (
                    "TEMP".into(),
                    std::env::temp_dir().to_string_lossy().into_owned(),
                ),
                (
                    "TMP".into(),
                    std::env::temp_dir().to_string_lossy().into_owned(),
                ),
            ],
        }
    }
}

// The native host supplies only its HWND. Script, runtime and asset locations
// are fixed; Flutter cannot supply a URL, token, executable, model or arguments.
#[cfg(windows)]
fn configuration(window: usize) -> Option<Configuration> {
    use windows_sys::Win32::System::SystemInformation::GetWindowsDirectoryW;
    let mut buffer = [0u16; 32768];
    let count = unsafe { GetWindowsDirectoryW(buffer.as_mut_ptr(), buffer.len() as u32) } as usize;
    if window == 0 || count == 0 || count >= buffer.len() {
        return None;
    }
    let windows = PathBuf::from(String::from_utf16(&buffer[..count]).ok()?);
    let app = std::env::current_exe().ok()?;
    let assets = PathBuf::from(std::env::var_os("LOCALAPPDATA")?)
        .join("Neura")
        .join("offline-text");
    if !assets.is_absolute() {
        return None;
    }
    let script = app
        .parent()?
        .join("offline-text")
        .join("Start-NeuraLocalConversation.ps1");
    let powershell = windows
        .join("System32")
        .join("WindowsPowerShell")
        .join("v1.0")
        .join("powershell.exe");
    if !script.is_file() || !powershell.is_file() {
        return None;
    }
    Some(Configuration {
        powershell,
        script,
        assets,
        window,
    })
}
#[cfg(not(windows))]
fn configuration(_: usize) -> Option<Configuration> {
    None
}

struct Owner {
    child: process::ChildProcess,
    reader: Option<JoinHandle<()>>,
    temporary: PathBuf,
}
impl Drop for Owner {
    fn drop(&mut self) {
        self.child.terminate();
        if let Some(reader) = self.reader.take() {
            let _ = reader.join();
        }
        let _ = std::fs::remove_dir_all(&self.temporary);
    }
}

async fn cancelled(cancel: &mut watch::Receiver<bool>) {
    if !*cancel.borrow_and_update() {
        let _ = cancel.changed().await;
    }
}

async fn run(
    config: Configuration,
    mut cancel: watch::Receiver<bool>,
    mut input: mpsc::Receiver<Zeroizing<String>>,
    grant: LocalTextGrant,
    state: Arc<State>,
    epoch: u64,
) -> Result<(), ()> {
    if *cancel.borrow() || !grant.is_active() {
        return Ok(());
    }
    let token = fresh_token()?;
    let temporary = std::env::temp_dir().join(format!("neura-local-app-{}", uuid::Uuid::new_v4()));
    let (child, pipe) = process::spawn_spec(&config.plan(&token, &temporary))?;
    let mut owner = Owner {
        child,
        reader: None,
        temporary,
    };
    let (sender, ready) = oneshot::channel();
    owner.reader = Some(
        thread::Builder::new()
            .name("neura-local-ready".into())
            .spawn(move || {
                let _ = sender.send(read_ready(pipe));
            })
            .map_err(|_| ())?,
    );
    let address = tokio::select! {
        biased;
        _ = cancelled(&mut cancel) => return Ok(()),
        result = tokio::time::timeout(START_TIMEOUT, ready) => result.map_err(|_| ())?.map_err(|_| ())??,
    };
    if !owner.child.is_running() || !grant.is_active() {
        return Err(());
    }
    let mut conversation =
        LocalConversation::new(address.port(), token, grant.clone()).map_err(|_| ())?;
    if !state.publish(epoch, IDLE, None) {
        return Ok(());
    }
    loop {
        tokio::select! {
            biased;
            _ = cancelled(&mut cancel) => break,
            text = input.recv() => {
                let Some(text) = text else { break; };
                if !owner.child.is_running() { return Err(()); }
                let reply = tokio::select! {
                    biased;
                    _ = cancelled(&mut cancel) => break,
                    result = conversation.reply(&text) => result.map_err(|_| ())?,
                };
                if !owner.child.is_running() || !grant.is_active() { return Err(()); }
                if !state.publish(epoch, IDLE, Some(reply)) { break; }
            },
            _ = tokio::time::sleep(Duration::from_millis(100)) => {
                if !owner.child.is_running() { return Err(()); }
            },
        }
    }
    conversation.stop();
    Ok(())
}

struct Active {
    cancel: watch::Sender<bool>,
    grant: LocalTextGrant,
    input: mpsc::Sender<Zeroizing<String>>,
    worker: JoinHandle<()>,
}
struct Launcher {
    state: Arc<State>,
    active: Option<Active>,
    blocked: bool,
}
impl Launcher {
    fn new() -> Self {
        Self {
            state: Arc::new(State::new()),
            active: None,
            blocked: false,
        }
    }
    fn end(&mut self, status: i32) {
        self.state.invalidate(status);
        if let Some(active) = self.active.take() {
            active.grant.revoke();
            active.cancel.send_replace(true);
            let _ = active.worker.join();
        }
    }
    fn stop(&mut self) {
        self.end(if self.blocked { BLOCKED } else { DISABLED });
    }
    fn block(&mut self) {
        self.blocked = true;
        self.stop();
    }
    fn start(&mut self, config: Option<Configuration>) -> i32 {
        if self.blocked {
            return BLOCKED;
        }
        // Always revoke/join the old owner before admitting a fresh text grant.
        self.stop();
        let Some(config) = config else {
            self.state.invalidate(UNAVAILABLE);
            return UNAVAILABLE;
        };
        let epoch = self.state.invalidate(STARTING);
        let state = self.state.clone();
        let grant = LocalTextGrant::approve_session_text();
        let worker_grant = grant.clone();
        let (cancel, receiver) = watch::channel(false);
        let (input, messages) = mpsc::channel(1);
        let worker = thread::Builder::new()
            .name("neura-local-text".into())
            .spawn(move || {
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    let runtime = tokio::runtime::Builder::new_current_thread()
                        .enable_all()
                        .build()
                        .map_err(|_| ())?;
                    tracing::subscriber::with_default(
                        tracing::subscriber::NoSubscriber::default(),
                        || {
                            runtime.block_on(run(
                                config,
                                receiver.clone(),
                                messages,
                                worker_grant.clone(),
                                state.clone(),
                                epoch,
                            ))
                        },
                    )
                }));
                worker_grant.revoke();
                if !*receiver.borrow() && !matches!(result, Ok(Ok(()))) {
                    state.publish(epoch, ERROR, None);
                }
            });
        match worker {
            Ok(worker) => {
                self.active = Some(Active {
                    cancel,
                    grant,
                    input,
                    worker,
                })
            }
            Err(_) => {
                grant.revoke();
                self.state.publish(epoch, ERROR, None);
            }
        }
        self.state.status()
    }
    fn submit(&mut self, text: &str) -> bool {
        if text.trim().is_empty() || text.len() > MAX_INPUT_BYTES || self.blocked {
            return false;
        }
        let Some(active) = &self.active else {
            return false;
        };
        let mut state = self.state.0.lock().unwrap_or_else(|p| p.into_inner());
        if state.status != IDLE || state.reply.is_some() || !active.grant.is_active() {
            return false;
        }
        if active
            .input
            .try_send(Zeroizing::new(text.to_owned()))
            .is_err()
        {
            return false;
        }
        state.status = WORKING;
        true
    }
}
impl Drop for Launcher {
    fn drop(&mut self) {
        self.stop();
    }
}

fn launcher() -> &'static Mutex<Launcher> {
    static LAUNCHER: OnceLock<Mutex<Launcher>> = OnceLock::new();
    LAUNCHER.get_or_init(|| Mutex::new(Launcher::new()))
}
#[no_mangle]
pub extern "C" fn neura_local_start(window: usize) -> i32 {
    launcher()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .start(configuration(window))
}
#[no_mangle]
pub extern "C" fn neura_local_status() -> i32 {
    launcher()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .state
        .status()
}
#[no_mangle]
pub extern "C" fn neura_local_stop() {
    launcher().lock().unwrap_or_else(|p| p.into_inner()).stop();
}
#[no_mangle]
pub extern "C" fn neura_local_block() {
    launcher().lock().unwrap_or_else(|p| p.into_inner()).block();
}
/// # Safety
/// `text` must reference `length` readable bytes for this call.
#[no_mangle]
pub unsafe extern "C" fn neura_local_submit(text: *const u8, length: usize) -> i32 {
    if text.is_null() || length == 0 || length > MAX_INPUT_BYTES {
        return 0;
    }
    let bytes = unsafe { std::slice::from_raw_parts(text, length) };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return 0;
    };
    i32::from(
        launcher()
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .submit(text),
    )
}
/// # Safety
/// `output` must reference `capacity` writable bytes. Replies are consumed once.
#[no_mangle]
pub unsafe extern "C" fn neura_local_take_reply(output: *mut u8, capacity: usize) -> usize {
    if output.is_null() || capacity < MAX_REPLY_BYTES {
        return 0;
    }
    let owner = launcher().lock().unwrap_or_else(|p| p.into_inner());
    let mut state = owner.state.0.lock().unwrap_or_else(|p| p.into_inner());
    if state.status != IDLE || owner.blocked {
        return 0;
    }
    let Some(reply) = state.reply.take() else {
        return 0;
    };
    if reply.len() > MAX_REPLY_BYTES {
        return 0;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(reply.as_ptr(), output, reply.len());
    }
    reply.len()
}

#[cfg(test)]
#[path = "local_session_tests.rs"]
mod tests;
