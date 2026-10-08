// Exercise the exact native implementation, including its real child process.
// No test-only credential/session operations are exported by the production ABI.
#[path = "../src/engine_session.rs"]
mod engine_session;

use engine_session::{
    fresh_token, process, read_ready, run_session, Launcher, RuntimeState, BLOCKED, DISABLED,
    ERROR, IDLE, PAUSED, STARTING, UNAVAILABLE, WORKING,
};
use std::{
    io::{Read, Write},
    net::TcpStream,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::sync::watch;

fn executable() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_neura_api"))
}

fn wait_idle(launcher: &Launcher) {
    let deadline = Instant::now() + Duration::from_secs(6);
    while matches!(launcher.status(), STARTING | WORKING) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(launcher.status(), IDLE);
}

fn wait_working(launcher: &Launcher) {
    let deadline = Instant::now() + Duration::from_secs(6);
    while launcher.status() == STARTING && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(2));
    }
    assert_eq!(launcher.status(), WORKING);
}

#[test]
fn pause_cancels_startup_and_active_work_and_only_resume_can_restart() {
    let mut launcher = Launcher::new(Some(executable()));
    launcher.set_foreground(true);
    assert_eq!(launcher.status(), DISABLED);
    assert_eq!(launcher.resume(), DISABLED);
    launcher.start();
    assert_eq!(launcher.pause(), PAUSED);
    std::thread::sleep(Duration::from_millis(600));
    assert_eq!(launcher.status(), PAUSED);
    assert_eq!(launcher.start(), PAUSED);
    assert_eq!(launcher.resume(), STARTING);
    wait_working(&launcher);
    for _ in 0..32 {
        assert_eq!(launcher.start(), WORKING);
    }
    let started = Instant::now();
    assert_eq!(launcher.pause(), PAUSED);
    assert!(started.elapsed() < Duration::from_secs(2));
    std::thread::sleep(Duration::from_millis(600));
    assert_eq!(launcher.status(), PAUSED);
    assert_eq!(launcher.pause(), PAUSED);
    assert_eq!(launcher.resume(), STARTING);
    wait_idle(&launcher);
    // No waiting queue or recurring synthetic work after completion.
    for _ in 0..32 {
        assert_eq!(launcher.start(), IDLE);
    }
    assert_eq!(launcher.pause(), PAUSED);
    launcher.stop();
    assert_eq!(launcher.status(), DISABLED);
    assert_eq!(launcher.resume(), DISABLED);
}

#[test]
fn foreground_and_safety_teardown_invalidate_working_and_paused_sessions() {
    for paused in [false, true] {
        for safety in [false, true] {
            let mut launcher = Launcher::new(Some(executable()));
            launcher.set_foreground(true);
            launcher.start();
            wait_working(&launcher);
            if paused {
                assert_eq!(launcher.pause(), PAUSED);
            }
            if safety {
                launcher.block();
            } else {
                launcher.set_foreground(false);
            }
            let expected = if safety { BLOCKED } else { DISABLED };
            assert_eq!(launcher.status(), expected);
            launcher.set_foreground(true);
            assert_eq!(launcher.status(), expected);
            assert_eq!(launcher.resume(), expected);
            assert_eq!(launcher.pause(), expected);
            std::thread::sleep(Duration::from_millis(600));
            assert_eq!(launcher.status(), expected);
        }
    }
}

#[test]
fn old_completions_errors_and_exhaustion_cannot_cross_generation_boundaries() {
    for next in [PAUSED, DISABLED, BLOCKED] {
        let state = RuntimeState::new();
        let old = state.invalidate(WORKING);
        state.invalidate(next);
        assert!(!state.publish(old, IDLE));
        assert!(!state.publish(old, ERROR));
        state.exhaust(old);
        assert_eq!(state.status(), next);
        let new = state.invalidate(STARTING);
        assert!(!state.publish(old, IDLE));
        state.exhaust(old);
        assert_eq!(state.status(), STARTING);
        assert!(state.publish(new, WORKING));
        state.exhaust(new);
        assert_eq!(state.status(), PAUSED);
        assert!(!state.publish(new, IDLE));
        assert!(!state.publish(new, ERROR));
    }
}

#[tokio::test]
async fn pause_during_real_probe_revokes_kills_and_discards_pending_completion() {
    let (cancel, receiver) = watch::channel(false);
    let state = Arc::new(RuntimeState::new());
    let generation = state.invalidate(STARTING);
    let observed = state.clone();
    let trigger = tokio::spawn(async move {
        tokio::time::timeout(Duration::from_secs(6), async {
            while observed.status() != WORKING {
                tokio::time::sleep(Duration::from_millis(2)).await;
            }
        })
        .await
        .unwrap();
        observed.invalidate(PAUSED);
        cancel.send_replace(true);
    });
    let (address, revoked) = run_session(executable(), receiver, state.clone(), generation)
        .await
        .unwrap()
        .unwrap();
    trigger.await.unwrap();
    assert!(revoked);
    assert!(TcpStream::connect_timeout(&address, Duration::from_millis(100)).is_err());
    assert_eq!(state.status(), PAUSED);
    assert!(!state.publish(generation, IDLE));
}

// Challenge the exact production budgets with controlled loopback peers. No
// test fixture selection, address or credential inspection enters the C ABI.
#[tokio::test]
async fn time_frame_and_byte_exhaustion_pause_and_invalidate_the_probe() {
    use futures_util::{SinkExt, StreamExt};
    use serde_json::json;
    use tokio_tungstenite::tungstenite::Message;
    for limit in ["time", "frames", "bytes", "invalid"] {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let peer = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut socket = tokio_tungstenite::accept_async(stream).await.unwrap();
            socket.next().await.unwrap().unwrap();
            if limit == "time" {
                // Wait for the client deadline to close rather than flushing.
                let _ = socket.next().await;
            } else if limit == "bytes" {
                socket.send(Message::Text("x".repeat(4097))).await.unwrap();
            } else if limit == "invalid" {
                socket.send(Message::Text("invalid".into())).await.unwrap();
            } else {
                socket
                    .send(Message::Text(
                        json!({"v":1,"kind":"hello","data":{"input_scope":"synthetic-only"}})
                            .to_string(),
                    ))
                    .await
                    .unwrap();
                socket.next().await.unwrap().unwrap();
                for _ in 0..16 {
                    socket
                        .send(Message::Text(
                            json!({"v":1,"kind":"speak_delta","data":{}}).to_string(),
                        ))
                        .await
                        .unwrap();
                }
            }
        });
        let state = RuntimeState::new();
        let generation = state.invalidate(WORKING);
        let started = Instant::now();
        let result =
            engine_session::bounded_probe(address, &fresh_token().unwrap(), &state, generation)
                .await;
        peer.await.unwrap();
        if limit == "invalid" {
            assert_eq!(result, Err(engine_session::ProbeFailure::Failed));
            assert_eq!(state.status(), WORKING);
        } else {
            assert_eq!(result, Err(engine_session::ProbeFailure::Exhausted));
            assert_eq!(state.status(), PAUSED);
            assert!(!state.publish(generation, IDLE));
            assert!(!state.publish(generation, ERROR));
        }
        assert!(started.elapsed() < Duration::from_secs(5));
    }
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
    let state = Arc::new(RuntimeState::new());
    let generation = state.invalidate(STARTING);
    let observed = state.clone();
    let trigger = tokio::spawn(async move {
        tokio::time::timeout(Duration::from_secs(6), async {
            while observed.status() != IDLE {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        cancel.send_replace(true);
    });
    let (address, revoked) = run_session(executable(), receiver, state, generation)
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
    let state = Arc::new(RuntimeState::new());
    let generation = state.invalidate(STARTING);
    assert!(run_session(
        PathBuf::from("missing-sidecar"),
        receiver,
        state,
        generation
    )
    .await
    .unwrap()
    .is_none());
}

#[test]
fn foreground_shutdown_never_restarts_and_safe_recovery_block_is_latched() {
    let mut launcher = Launcher::new(Some(executable()));
    assert_eq!(launcher.start(), BLOCKED);
    launcher.set_foreground(true);
    assert_eq!(launcher.start(), STARTING);
    wait_idle(&launcher);
    launcher.set_foreground(false);
    assert_eq!(launcher.status(), DISABLED);
    launcher.set_foreground(true);
    assert_eq!(launcher.status(), DISABLED);
    assert_eq!(launcher.start(), STARTING);
    wait_idle(&launcher);
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
        assert_eq!(launcher.status(), DISABLED);
    }
    assert_eq!(launcher.start(), STARTING);
    wait_idle(&launcher);
    let started = Instant::now();
    launcher.stop();
    assert!(started.elapsed() < Duration::from_secs(2));
    assert_eq!(launcher.status(), DISABLED);
}

#[test]
fn missing_binary_fails_without_retry_or_external_fallback() {
    let mut launcher = Launcher::new(Some(PathBuf::from("missing-sidecar")));
    launcher.set_foreground(true);
    assert_eq!(launcher.start(), STARTING);
    let deadline = Instant::now() + Duration::from_secs(2);
    while matches!(launcher.status(), STARTING | WORKING) && Instant::now() < deadline {
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
        wait_idle(&launcher);
        launcher.stop();
    });
    assert!(
        buffer.0.lock().unwrap().is_empty(),
        "Native session traffic must not enter tracing output."
    );
}
