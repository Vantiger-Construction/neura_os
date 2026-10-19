// Exercise the exact native implementation, including its real child process.
// No test-only credential/session operations are exported by the production ABI.
#[path = "../src/engine_session.rs"]
mod engine_session;

use engine_session::{
    fresh_token, process, read_ready, run_session, CheckMode, Launcher, RuntimeState, BLOCKED,
    DISABLED, ERROR, IDLE, MODEL_UNAVAILABLE, PAUSED, STARTING, UNAVAILABLE, WORKING,
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

#[test]
fn generic_native_plan_owns_and_reaps_a_real_child() {
    let token = fresh_token().unwrap();
    let spec = process::SpawnSpec {
        executable: executable(),
        arguments: Vec::new(),
        environment: vec![
            ("NEURA_API_ADDR".into(), "127.0.0.1:0".into()),
            ("NEURA_API_LAUNCHER_READY".into(), "1".into()),
            ("NEURA_API_SESSION_TOKEN".into(), token.to_string()),
        ],
    };
    let (mut child, pipe) = process::spawn_spec(&spec).unwrap();
    let address = read_ready(pipe).unwrap();
    assert!(child.is_running());
    child.terminate();
    assert!(!child.is_running());
    assert!(TcpStream::connect_timeout(&address, Duration::from_millis(500)).is_err());
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
    let (address, revoked) = run_session(
        executable(),
        CheckMode::Echo,
        receiver,
        state.clone(),
        generation,
    )
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
        let result = engine_session::bounded_probe(
            address,
            &fresh_token().unwrap(),
            CheckMode::Echo,
            &state,
            generation,
        )
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
    let (address, revoked) =
        run_session(executable(), CheckMode::Echo, receiver, state, generation)
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
        CheckMode::Echo,
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
    let (child, mut pipe) = process::spawn(&executable(), &token, false).unwrap();
    let address = read_ready(&mut pipe).unwrap();
    assert!(TcpStream::connect_timeout(&address, Duration::from_secs(1)).is_ok());
    #[cfg(not(windows))]
    {
        let plan = process::platform::spawn_plan(&executable(), &token, false);
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
        assert!(
            plan.get_envs()
                .all(|(key, _)| key != "NEURA_API_MODEL_ADAPTER"),
            "An ordinary start never selects the local adapter."
        );
        // The local check adds exactly the one fixed adapter value.
        let local = process::platform::spawn_plan(&executable(), &token, true);
        assert_eq!(local.get_args().count(), 0);
        assert_eq!(local.get_envs().count(), 4);
        assert!(local
            .get_envs()
            .any(|(key, value)| key == "NEURA_API_MODEL_ADAPTER"
                && value.is_some_and(|value| value == "ollama-local")));
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

// ---- Milestone 2: explicitly selected local model check --------------------

fn wait_settled(launcher: &Launcher, timeout: Duration) -> i32 {
    let deadline = Instant::now() + timeout;
    while matches!(launcher.status(), STARTING | WORKING) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(10));
    }
    launcher.status()
}

/// True when a real Ollama daemon could answer the local check on this host.
/// Only the measured Windows target admits the model; elsewhere the sidecar
/// always reports it unavailable. Tests never run a real model.
fn host_may_serve_model() -> bool {
    cfg!(windows)
        && TcpStream::connect_timeout(
            &"127.0.0.1:11434".parse().unwrap(),
            Duration::from_millis(300),
        )
        .is_ok()
}

/// Launch a real sidecar through the native spawn plan and read its `hello`.
async fn child_hello(local_model: bool) -> serde_json::Value {
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::{client::IntoClientRequest, Message};
    let token = fresh_token().unwrap();
    let (mut child, pipe) = process::spawn(&executable(), &token, local_model).unwrap();
    let address = tokio::task::spawn_blocking(move || read_ready(pipe))
        .await
        .unwrap()
        .unwrap();
    let mut request = format!("ws://{address}/").into_client_request().unwrap();
    request.headers_mut().insert(
        "Authorization",
        format!("Bearer {}", token.as_str()).parse().unwrap(),
    );
    let (mut socket, _) = tokio_tungstenite::connect_async(request).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::json!({"v":1,"kind":"hello","data":{}}).to_string(),
        ))
        .await
        .unwrap();
    let Some(Ok(Message::Text(text))) = socket.next().await else {
        panic!("expected a hello envelope");
    };
    child.terminate();
    serde_json::from_str(&text).unwrap()
}

// Proves the launcher wiring on every platform without contacting Ollama:
// only the local entry point starts a sidecar with the local adapter.
#[tokio::test]
async fn only_the_local_spawn_plan_starts_the_local_adapter() {
    assert_eq!(
        child_hello(true).await["data"]["model_adapter"],
        "ollama-local"
    );
    assert_eq!(child_hello(false).await["data"]["model_adapter"], "echo");
}

// Where no daemon can answer, a correctly wired local launch must end as the
// distinct model-unavailable state rather than an echo-mode success or error.
#[test]
fn local_check_without_a_model_reports_model_unavailable() {
    let mut launcher = Launcher::new(Some(executable()));
    launcher.set_foreground(true);
    assert_eq!(launcher.start_local(), STARTING);
    assert_eq!(launcher.mode(), CheckMode::Local);
    if host_may_serve_model() {
        // Never load the operator's real model from a test.
        launcher.stop();
        assert_eq!(launcher.status(), DISABLED);
        return;
    }
    assert_eq!(
        wait_settled(&launcher, Duration::from_secs(10)),
        MODEL_UNAVAILABLE
    );
    // The session was torn down; a new explicit start is required.
    std::thread::sleep(Duration::from_millis(300));
    assert_eq!(launcher.status(), MODEL_UNAVAILABLE);

    // Echo remains the default for an ordinary start.
    assert_eq!(launcher.start(), STARTING);
    assert_eq!(launcher.mode(), CheckMode::Echo);
    wait_idle(&launcher);
    launcher.stop();
    assert_eq!(launcher.status(), DISABLED);
}

#[test]
fn resume_keeps_the_explicitly_selected_adapter_and_safety_still_blocks() {
    let mut launcher = Launcher::new(Some(executable()));
    launcher.set_foreground(true);
    launcher.start_local();
    assert_eq!(launcher.pause(), PAUSED);
    // Start cannot bypass Pause in either mode.
    assert_eq!(launcher.start_local(), PAUSED);
    assert_eq!(launcher.start(), PAUSED);
    assert_eq!(launcher.resume(), STARTING);
    assert_eq!(launcher.mode(), CheckMode::Local);
    // Stop before the check can reach a real daemon.
    launcher.stop();
    assert_eq!(launcher.status(), DISABLED);

    launcher.set_foreground(false);
    assert_eq!(launcher.start_local(), BLOCKED);
    launcher.set_foreground(true);
    launcher.block();
    assert_eq!(launcher.start_local(), BLOCKED);
    assert_eq!(launcher.status(), BLOCKED);
}

/// Controlled loopback stand-in for a sidecar answering the local check.
async fn local_peer(
    hello_adapter: &'static str,
    model_mode: &'static str,
    run: Vec<serde_json::Value>,
) -> (
    std::net::SocketAddr,
    tokio::task::JoinHandle<Vec<serde_json::Value>>,
) {
    use futures_util::{SinkExt, StreamExt};
    use serde_json::json;
    use tokio_tungstenite::tungstenite::Message;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let peer = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let mut socket = tokio_tungstenite::accept_async(stream).await.unwrap();
        let mut seen = Vec::new();
        while let Some(Ok(Message::Text(text))) = socket.next().await {
            let request: serde_json::Value = serde_json::from_str(&text).unwrap();
            seen.push(request.clone());
            let replies = match request["kind"].as_str().unwrap() {
                "hello" => vec![json!({"v":1,"kind":"hello","data":{
                    "input_scope":"synthetic-only","model_adapter":hello_adapter}})],
                "diagnostics_request" => vec![json!({"v":1,"kind":"diagnostics","data":{
                    "input_scope":"synthetic-only","model_mode":model_mode,"checks":[]}})],
                "synthetic_input" => run.clone(),
                _ => vec![],
            };
            for reply in replies {
                if socket.send(Message::Text(reply.to_string())).await.is_err() {
                    return seen;
                }
            }
        }
        seen
    });
    (address, peer)
}

async fn local_probe(address: std::net::SocketAddr) -> Result<(), engine_session::ProbeFailure> {
    let state = RuntimeState::new();
    let generation = state.invalidate(WORKING);
    engine_session::bounded_probe(
        address,
        &fresh_token().unwrap(),
        CheckMode::Local,
        &state,
        generation,
    )
    .await
}

#[tokio::test]
async fn local_probe_accepts_a_verified_model_completion() {
    use serde_json::json;
    let (address, peer) = local_peer(
        "ollama-local",
        "local",
        vec![
            json!({"v":1,"kind":"speak_delta","data":{"delta":"The link "}}),
            json!({"v":1,"kind":"speak_delta","data":{"delta":"works."}}),
            json!({"v":1,"kind":"speak","data":{"text":"The link works."}}),
        ],
    )
    .await;
    assert_eq!(local_probe(address).await, Ok(()));
    let seen = peer.await.unwrap();
    let kinds: Vec<_> = seen.iter().map(|r| r["kind"].as_str().unwrap()).collect();
    // Diagnostics before the fixture, and only the fixed fixture is submitted.
    assert_eq!(kinds, ["hello", "diagnostics_request", "synthetic_input"]);
    assert_eq!(seen[2]["data"], json!({"fixture":"hello"}));
}

#[tokio::test]
async fn local_probe_reports_unavailable_models_before_submitting_a_fixture() {
    let (address, peer) = local_peer("ollama-local", "unavailable", vec![]).await;
    assert_eq!(
        local_probe(address).await,
        Err(engine_session::ProbeFailure::ModelUnavailable)
    );
    let seen = peer.await.unwrap();
    assert!(seen.iter().all(|r| r["kind"] != "synthetic_input"));
}

#[tokio::test]
async fn local_probe_maps_run_errors_and_rejects_an_echo_sidecar() {
    use engine_session::ProbeFailure;
    use serde_json::json;
    let error = |data: serde_json::Value| json!({"v":1,"kind":"error","data":data});
    for (adapter, run, expected) in [
        (
            "ollama-local",
            vec![error(
                json!({"message":"model adapter unavailable","code":"not_installed"}),
            )],
            ProbeFailure::ModelUnavailable,
        ),
        (
            "ollama-local",
            vec![error(json!({"message":"model output exceeded budget"}))],
            ProbeFailure::Exhausted,
        ),
        (
            "ollama-local",
            vec![error(json!({"message":"model request timed out"}))],
            ProbeFailure::Exhausted,
        ),
        (
            "ollama-local",
            vec![error(json!({"message":"model request failed"}))],
            ProbeFailure::Failed,
        ),
        (
            "ollama-local",
            vec![json!({"v":1,"kind":"speak","data":{"text":"   "}})],
            ProbeFailure::Failed,
        ),
        // A sidecar launched without the local adapter must never pass.
        ("echo", vec![], ProbeFailure::Failed),
    ] {
        let (address, peer) = local_peer(adapter, "local", run).await;
        assert_eq!(local_probe(address).await, Err(expected));
        peer.abort();
    }
}

#[tokio::test]
async fn local_probe_frame_budget_pauses_the_session() {
    use serde_json::json;
    let deltas = vec![
        json!({"v":1,"kind":"speak_delta","data":{"delta":"x"}});
        engine_session::LOCAL_MAX_FIXTURE_FRAMES
    ];
    let (address, peer) = local_peer("ollama-local", "local", deltas).await;
    let state = RuntimeState::new();
    let generation = state.invalidate(WORKING);
    let result = engine_session::bounded_probe(
        address,
        &fresh_token().unwrap(),
        CheckMode::Local,
        &state,
        generation,
    )
    .await;
    assert_eq!(result, Err(engine_session::ProbeFailure::Exhausted));
    assert_eq!(state.status(), PAUSED);
    assert!(!state.publish(generation, IDLE));
    peer.abort();
}
