// Exercise the exact native implementation, including its real child process.
// No test-only credential/session operations are exported by the production ABI.
#[path = "../src/engine_session.rs"]
mod engine_session;

use engine_session::{
    fresh_token, process, read_ready, run_session, Launcher, BLOCKED, ERROR, READY, STARTING,
    STOPPED, UNAVAILABLE,
};
use std::{
    io::{Read, Write},
    net::TcpStream,
    path::PathBuf,
    sync::{
        atomic::{AtomicI32, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
use tokio::sync::watch;

fn executable() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_neura_api"))
}

fn wait_ready(launcher: &Launcher) {
    let deadline = Instant::now() + Duration::from_secs(6);
    while launcher.status() == STARTING && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(launcher.status(), READY);
}

#[test]
fn fresh_native_credentials_have_32_random_bytes_and_are_not_reused() {
    let first = fresh_token().unwrap();
    let second = fresh_token().unwrap();
    assert_eq!(first.len(), 64);
    assert!(first.bytes().all(|byte| byte.is_ascii_hexdigit()));
    assert!(first.as_str() != second.as_str());
}

#[test]
fn readiness_rejects_untrusted_addresses_malformed_and_oversized_receipts() {
    assert_eq!(
        read_ready(b"NEURA_IPC_READY 127.0.0.1:12345\n".as_slice())
            .unwrap()
            .port(),
        12345
    );
    for invalid in [
        "NEURA_IPC_READY 0.0.0.0:12\n",
        "NEURA_IPC_READY 192.168.1.1:12\n",
        "NEURA_IPC_READY 127.0.0.1:0\n",
        "NEURA_IPC_READY localhost:12\n",
        "log line\n",
        "NEURA_IPC_READY [::1]:12\n",
    ] {
        assert!(read_ready(invalid.as_bytes()).is_err());
    }
    assert!(read_ready([b'x'; 81].as_slice()).is_err());
}

#[tokio::test]
async fn real_session_verifies_hello_diagnostics_revokes_and_terminates() {
    let (cancel, receiver) = watch::channel(false);
    let state = Arc::new(AtomicI32::new(STARTING));
    let observed = state.clone();
    let trigger = tokio::spawn(async move {
        tokio::time::timeout(Duration::from_secs(6), async {
            while observed.load(Ordering::SeqCst) != READY {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        cancel.send_replace(true);
    });
    let (address, revoked) = run_session(executable(), receiver, state)
        .await
        .unwrap()
        .unwrap();
    trigger.await.unwrap();
    assert!(
        revoked,
        "The real authenticated revoke endpoint must return 204."
    );
    assert!(TcpStream::connect_timeout(&address, Duration::from_millis(100)).is_err());
}

#[tokio::test]
async fn cancellation_before_launch_prevents_child_creation() {
    let (_, receiver) = watch::channel(true);
    let state = Arc::new(AtomicI32::new(STARTING));
    assert!(
        run_session(PathBuf::from("missing-sidecar"), receiver, state)
            .await
            .unwrap()
            .is_none()
    );
}

#[test]
fn foreground_shutdown_never_restarts_and_safe_recovery_block_is_latched() {
    let mut launcher = Launcher::new(Some(executable()));
    assert_eq!(launcher.start(), BLOCKED);
    launcher.set_foreground(true);
    assert_eq!(launcher.start(), STARTING);
    wait_ready(&launcher);
    launcher.set_foreground(false);
    assert_eq!(launcher.status(), STOPPED);
    launcher.set_foreground(true);
    assert_eq!(launcher.status(), STOPPED);
    assert_eq!(launcher.start(), STARTING);
    wait_ready(&launcher);
    launcher.block();
    assert_eq!(launcher.status(), BLOCKED);
    launcher.set_foreground(true);
    assert_eq!(launcher.start(), BLOCKED);
    launcher.stop();
    assert_eq!(launcher.status(), BLOCKED);
}

#[test]
fn stop_during_startup_joins_old_generation_and_allows_only_explicit_restart() {
    let mut launcher = Launcher::new(Some(executable()));
    launcher.set_foreground(true);
    for _ in 0..5 {
        assert_eq!(launcher.start(), STARTING);
        launcher.stop();
        assert_eq!(launcher.status(), STOPPED);
    }
    assert_eq!(launcher.start(), STARTING);
    wait_ready(&launcher);
    let started = Instant::now();
    launcher.stop();
    assert!(started.elapsed() < Duration::from_secs(2));
    assert_eq!(launcher.status(), STOPPED);
}

#[test]
fn missing_binary_fails_without_retry_or_external_fallback() {
    let mut launcher = Launcher::new(Some(PathBuf::from("missing-sidecar")));
    launcher.set_foreground(true);
    assert_eq!(launcher.start(), STARTING);
    let deadline = Instant::now() + Duration::from_secs(2);
    while launcher.status() == STARTING && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(launcher.status(), ERROR);
    launcher.stop();
    let mut unavailable = Launcher::new(None);
    unavailable.set_foreground(true);
    assert_eq!(unavailable.start(), UNAVAILABLE);
}

#[test]
fn owner_drop_kills_real_child_and_pipe_contains_no_credential_or_logs() {
    let token = fresh_token().unwrap();
    let (child, mut pipe) = process::spawn(&executable(), &token).unwrap();
    let address = read_ready(&mut pipe).unwrap();
    assert!(TcpStream::connect_timeout(&address, Duration::from_secs(1)).is_ok());
    #[cfg(not(windows))]
    {
        let plan = process::platform::spawn_plan(&executable(), &token);
        assert_eq!(
            plan.get_args().count(),
            0,
            "Credentials cannot enter child arguments."
        );
        assert_eq!(
            plan.get_envs().count(),
            3,
            "The child environment must be an allowlist."
        );
        assert!(plan
            .get_envs()
            .any(|(key, value)| key == "NEURA_API_SESSION_TOKEN"
                && value.is_some_and(|value| value == token.as_str())));
    }
    drop(child);
    assert!(TcpStream::connect_timeout(&address, Duration::from_millis(100)).is_err());
    let mut remaining = Vec::new();
    pipe.take(4096).read_to_end(&mut remaining).unwrap();
    assert!(
        remaining.is_empty(),
        "Readiness stdout must carry no dependency traces or results."
    );
}

#[tokio::test]
async fn failed_or_stalled_revocation_is_bounded_for_termination_fallback() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let started = Instant::now();
    assert!(engine_session::revoke(address, &fresh_token().unwrap())
        .await
        .is_err());
    assert!(started.elapsed() < Duration::from_secs(1));
}

#[derive(Clone)]
struct TraceBuffer(Arc<Mutex<Vec<u8>>>);
impl Write for TraceBuffer {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[test]
fn native_owner_emits_no_credentials_or_wire_data_even_with_parent_trace_logging() {
    let buffer = TraceBuffer(Arc::new(Mutex::new(Vec::new())));
    let writer = buffer.clone();
    let subscriber = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::TRACE)
        .with_writer(move || writer.clone())
        .without_time()
        .finish();
    tracing::subscriber::with_default(subscriber, || {
        let mut launcher = Launcher::new(Some(executable()));
        launcher.set_foreground(true);
        launcher.start();
        wait_ready(&launcher);
        launcher.stop();
    });
    assert!(
        buffer.0.lock().unwrap().is_empty(),
        "Native session traffic must not enter tracing output."
    );
}
