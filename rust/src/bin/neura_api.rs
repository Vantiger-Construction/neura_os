use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        ConnectInfo, State,
    },
    http::{header, HeaderMap, StatusCode},
    response::Response,
    routing::{get, post},
    Router,
};
use futures_util::{Sink, SinkExt, StreamExt};
use neura_swarm::local_model::{self, ModelUnavailable, StreamError, StreamLimits};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use subtle::ConstantTimeEq;
use tokio::{
    net::TcpListener,
    sync::{mpsc, watch, Semaphore},
    task::JoinHandle,
};
use tracing::{info, warn};
use uuid::Uuid;

const OUTBOUND_CAPACITY: usize = 32;
const MAX_MESSAGE_BYTES: usize = 4096;
const MAX_CLIENTS: usize = 4;
const WRITE_TIMEOUT: Duration = Duration::from_secs(2);

// Milestone 2 local model adapter budgets. See docs/NEURA_ENGINE_MODEL_ADAPTER_M2.md.
const MODEL_ADAPTER_ENV: &str = "NEURA_API_MODEL_ADAPTER";
const PROBE_DEADLINE: Duration = Duration::from_secs(3);
const LOCAL_RUN_DEADLINE: Duration = Duration::from_secs(60);
const MAX_MODEL_OUTPUT: usize = 3_000;
const MAX_MODEL_LINE: usize = 4_096;
const DELTA_FLUSH_BYTES: usize = 48;
const DELTA_FLUSH_INTERVAL: Duration = Duration::from_millis(60);
const FIXTURE_SYSTEM: &str = "You are the Neura engine running a synthetic self-check. \
Follow only the instruction given. Do not ask questions.";

/// Which model adapter this process was explicitly launched with. Selected once
/// at startup by the trusted launcher; never changeable over IPC.
#[derive(Clone)]
enum Adapter {
    /// Default: fixed repository echo text, no model.
    Echo,
    /// Opt-in: the pinned model on the operator's loopback Ollama daemon.
    Local(Arc<LocalAdapter>),
}

impl Adapter {
    fn from_setting(value: Option<&str>) -> Result<Self, &'static str> {
        match value {
            None | Some("echo") => Ok(Self::Echo),
            Some("ollama-local") => Ok(Self::Local(Arc::new(LocalAdapter::new(
                local_model::ENDPOINT.into(),
                local_model::memory_admitted,
            )))),
            Some(_) => Err("NEURA_API_MODEL_ADAPTER must be echo or ollama-local"),
        }
    }

    fn name(&self) -> &'static str {
        match self {
            Self::Echo => "echo",
            Self::Local(_) => "ollama-local",
        }
    }
}

/// Content-free record of the most recent local run. Never holds model text.
#[derive(Clone, Copy)]
struct RunRecord {
    fixture: &'static str,
    outcome: &'static str,
    ttft_ms: Option<u64>,
    total_ms: u64,
    output_bytes: usize,
}

struct LocalAdapter {
    endpoint: String,
    admit: fn() -> bool,
    last_run: Mutex<Option<RunRecord>>,
}

impl LocalAdapter {
    fn new(endpoint: String, admit: fn() -> bool) -> Self {
        Self {
            endpoint,
            admit,
            last_run: Mutex::new(None),
        }
    }

    /// Admission plus pinned-model verification. Sends only the model name.
    async fn probe(&self) -> Result<(), ModelUnavailable> {
        if !(self.admit)() {
            return Err(ModelUnavailable::InsufficientMemory);
        }
        let client =
            local_model::client(PROBE_DEADLINE).map_err(|_| ModelUnavailable::Unreachable)?;
        tokio::time::timeout(
            PROBE_DEADLINE,
            local_model::verify_pinned_model(&client, &self.endpoint),
        )
        .await
        .unwrap_or(Err(ModelUnavailable::Unreachable))
    }

    fn last_run(&self) -> Option<RunRecord> {
        *self.last_run.lock().unwrap_or_else(|p| p.into_inner())
    }
}

/// Records a run when dropped, so an aborted (cancelled) task is still counted.
struct RunGuard {
    local: Arc<LocalAdapter>,
    fixture: &'static str,
    started: Instant,
    ttft: Option<Duration>,
    output_bytes: usize,
    outcome: &'static str,
}

impl Drop for RunGuard {
    fn drop(&mut self) {
        let record = RunRecord {
            fixture: self.fixture,
            outcome: self.outcome,
            ttft_ms: self.ttft.map(|d| d.as_millis() as u64),
            total_ms: self.started.elapsed().as_millis() as u64,
            output_bytes: self.output_bytes,
        };
        *self
            .local
            .last_run
            .lock()
            .unwrap_or_else(|p| p.into_inner()) = Some(record);
    }
}

#[derive(Clone)]
struct AppState {
    session: Session,
    adapter: Adapter,
}

// Supplied by an explicit trusted launcher, never by a URL or a built-in default.
// Do not derive Debug: the session credential must not appear in diagnostics.
#[derive(Clone)]
struct Session {
    token: Arc<str>,
    active: watch::Sender<bool>,
    clients: Arc<Semaphore>,
}

impl Session {
    fn new(token: String) -> Result<Self, &'static str> {
        if token.len() != 64 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err("NEURA_API_SESSION_TOKEN must be 64 hexadecimal characters");
        }
        let (active, _) = watch::channel(true);
        Ok(Self {
            token: token.into(),
            active,
            clients: Arc::new(Semaphore::new(MAX_CLIENTS)),
        })
    }

    fn is_active(&self) -> bool {
        *self.active.borrow()
    }

    fn authorize(&self, peer: SocketAddr, headers: &HeaderMap) -> Result<(), StatusCode> {
        if !peer.ip().is_loopback() || headers.contains_key(header::ORIGIN) {
            return Err(StatusCode::FORBIDDEN);
        }
        let mut values = headers.get_all(header::AUTHORIZATION).iter();
        let token = values
            .next()
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.strip_prefix("Bearer "));
        if values.next().is_some()
            || !self.is_active()
            || !token.is_some_and(|token| bool::from(token.as_bytes().ct_eq(self.token.as_bytes())))
        {
            return Err(StatusCode::UNAUTHORIZED);
        }
        Ok(())
    }

    fn revoke(&self) {
        self.active.send_replace(false);
    }

    async fn revoked(&self) {
        let mut active = self.active.subscribe();
        if *active.borrow_and_update() {
            let _ = active.changed().await;
        }
    }
}

fn local_address(value: &str) -> Result<SocketAddr, &'static str> {
    let address: SocketAddr = value.parse().map_err(|_| "invalid NEURA_API_ADDR")?;
    if !address.ip().is_loopback() {
        return Err("NEURA_API_ADDR must be a numeric loopback address");
    }
    Ok(address)
}

async fn bind_local(value: &str) -> std::io::Result<TcpListener> {
    // Validate before bind, including wildcard and IPv6 addresses. No DNS lookup.
    let address = local_address(value).map_err(std::io::Error::other)?;
    TcpListener::bind(address).await
}

fn app_with(session: Session, adapter: Adapter) -> Router {
    Router::new()
        .route("/", get(ws_handler))
        .route("/session/revoke", post(revoke_session))
        .with_state(AppState { session, adapter })
}

async fn ws_handler(
    State(AppState { session, adapter }): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Result<Response, StatusCode> {
    session.authorize(peer, &headers)?;
    let permit = session
        .clients
        .clone()
        .try_acquire_owned()
        .map_err(|_| StatusCode::TOO_MANY_REQUESTS)?;
    Ok(ws
        .max_message_size(MAX_MESSAGE_BYTES)
        .max_frame_size(MAX_MESSAGE_BYTES)
        .write_buffer_size(0)
        .max_write_buffer_size(MAX_MESSAGE_BYTES * 2)
        .on_upgrade(move |socket| async move {
            let _permit = permit;
            client(socket, session, adapter).await;
        }))
}

async fn revoke_session(
    State(AppState { session, .. }): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
) -> Result<StatusCode, StatusCode> {
    session.authorize(peer, &headers)?;
    session.revoke();
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
struct InEnvelope {
    #[allow(dead_code)]
    v: Option<u32>,
    kind: String,
    #[allow(dead_code)]
    id: Option<String>,
    #[serde(default)]
    data: Value,
}

#[derive(Serialize)]
struct OutEnvelope<'a> {
    v: u32,
    kind: &'a str,
    id: String,
    data: Value,
}

fn frame(kind: &str, data: Value) -> String {
    serde_json::to_string(&OutEnvelope {
        v: 1,
        kind,
        id: Uuid::new_v4().to_string(),
        data,
    })
    .expect("serialize envelope")
}

#[derive(Clone)]
struct Outbound {
    sender: mpsc::Sender<String>,
    stopped: watch::Sender<bool>,
    session: Session,
}

impl Outbound {
    fn new(session: Session) -> (Self, mpsc::Receiver<String>) {
        let (sender, receiver) = mpsc::channel(OUTBOUND_CAPACITY);
        let (stopped, _) = watch::channel(false);
        (
            Self {
                sender,
                stopped,
                session,
            },
            receiver,
        )
    }

    fn stop(&self) {
        self.stopped.send_replace(true);
    }

    fn is_active(&self) -> bool {
        self.session.is_active() && !*self.stopped.borrow()
    }

    async fn ended(&self) {
        let mut stopped = self.stopped.subscribe();
        if !*stopped.borrow_and_update() {
            let _ = stopped.changed().await;
        }
    }

    fn send(&self, text: String) -> bool {
        if !self.is_active() {
            return false;
        }
        if text.len() > MAX_MESSAGE_BYTES || self.sender.try_send(text).is_err() {
            // Never wait for space or try to queue an error into a full queue.
            // The owner closes the connection, aborts work and discards results.
            self.stop();
            warn!("sidecar outbound delivery unavailable; closing client");
            return false;
        }
        true
    }
}

// Dropping a JoinHandle normally detaches its task. Own both tasks explicitly so
// cancellation of the connection owner cannot leave generation or delivery alive.
struct OwnedTask(JoinHandle<()>);

impl OwnedTask {
    async fn stop(mut self) {
        self.0.abort();
        let _ = (&mut self.0).await;
    }
}

impl Drop for OwnedTask {
    fn drop(&mut self) {
        self.0.abort();
    }
}

struct StopOnDrop(Outbound);

impl Drop for StopOnDrop {
    fn drop(&mut self) {
        self.0.stop();
    }
}

async fn write_outbound<S>(mut socket: S, mut receiver: mpsc::Receiver<String>, out: Outbound)
where
    S: Sink<Message> + Unpin,
{
    // A failed or cancelled writer must also wake the connection owner.
    let _stop = StopOnDrop(out.clone());
    loop {
        let text = tokio::select! {
            biased;
            _ = out.session.revoked() => break,
            _ = out.ended() => break,
            text = receiver.recv() => match text {
                Some(text) => text,
                None => break,
            },
        };
        if !out.is_active() {
            break;
        }
        let sent = tokio::select! {
            biased;
            _ = out.session.revoked() => break,
            _ = out.ended() => break,
            result = tokio::time::timeout(WRITE_TIMEOUT, socket.send(Message::Text(text))) => result,
        };
        if !matches!(sent, Ok(Ok(()))) {
            break;
        }
    }
    out.stop();
    // Drop the sink and receiver; do not flush or replay pending output.
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SyntheticInput {
    fixture: SyntheticFixture,
}

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum SyntheticFixture {
    Hello,
    Stream,
}

impl SyntheticFixture {
    fn name(self) -> &'static str {
        match self {
            Self::Hello => "hello",
            Self::Stream => "stream",
        }
    }

    /// Fixed, repository-defined model instruction. No caller text is admitted.
    fn model_prompt(self) -> &'static str {
        match self {
            Self::Hello => {
                "Reply with one short, friendly sentence confirming that the local Neura engine link works."
            }
            Self::Stream => "In about 80 words of plain prose, explain how ocean tides work.",
        }
    }

    fn model_payload(self) -> Value {
        json!({
            "model": local_model::LOCAL_MODEL,
            "messages": [
                {"role": "system", "content": FIXTURE_SYSTEM},
                {"role": "user", "content": self.model_prompt()},
            ],
            "stream": true,
            "keep_alive": 0,
            "options": {"num_ctx": 2048, "num_predict": 192, "num_thread": 2, "temperature": 0.2},
        })
    }
}

fn spawn_local(fixture: SyntheticFixture, out: Outbound, local: Arc<LocalAdapter>) -> OwnedTask {
    OwnedTask(tokio::spawn(async move {
        // Dropped on completion or abort; abort (cancel/revoke) records "cancelled".
        let mut run = RunGuard {
            local: local.clone(),
            fixture: fixture.name(),
            started: Instant::now(),
            ttft: None,
            output_bytes: 0,
            outcome: "cancelled",
        };
        // Re-verify before every run: a tag can be replaced after diagnostics.
        // There is no echo or cloud fallback when the pinned model is missing.
        let verified = tokio::select! {
            biased;
            _ = out.session.revoked() => return,
            _ = out.ended() => return,
            result = local.probe() => result,
        };
        if let Err(reason) = verified {
            run.outcome = "unavailable";
            out.send(frame(
                "error",
                json!({"message":"model adapter unavailable","code":reason.code()}),
            ));
            return;
        }
        let Ok(client) = local_model::client(LOCAL_RUN_DEADLINE) else {
            run.outcome = "failed";
            out.send(frame("error", json!({"message":"model request failed"})));
            return;
        };
        let id = Uuid::new_v4().to_string();
        let payload = fixture.model_payload();
        let limits = StreamLimits {
            max_line: MAX_MODEL_LINE,
            max_output: MAX_MODEL_OUTPUT,
        };
        let mut pending = String::new();
        // None until the first delta, which is always delivered immediately.
        let mut last_flush: Option<Instant> = None;
        let started = run.started;
        let (mut ttft, mut output_bytes) = (None, 0usize);
        let result = {
            let stream =
                local_model::stream_chat(&client, &local.endpoint, &payload, limits, |delta| {
                    ttft.get_or_insert_with(|| started.elapsed());
                    output_bytes += delta.len();
                    pending.push_str(delta);
                    // Coalesce token-sized deltas so a fast model cannot fill the
                    // bounded outbound queue faster than the eager writer drains it.
                    if pending.len() < DELTA_FLUSH_BYTES
                        && last_flush.is_some_and(|at| at.elapsed() < DELTA_FLUSH_INTERVAL)
                    {
                        return true;
                    }
                    last_flush = Some(Instant::now());
                    let delta = std::mem::take(&mut pending);
                    out.send(frame(
                        "speak_delta",
                        json!({"utterance_id":id,"delta":delta}),
                    ))
                });
            tokio::select! {
                biased;
                _ = out.session.revoked() => return,
                _ = out.ended() => return,
                result = tokio::time::timeout(LOCAL_RUN_DEADLINE, stream) => result,
            }
        };
        run.ttft = ttft;
        run.output_bytes = output_bytes;
        match result {
            Ok(Ok(text)) => {
                if !pending.is_empty()
                    && !out.send(frame(
                        "speak_delta",
                        json!({"utterance_id":id,"delta":std::mem::take(&mut pending)}),
                    ))
                {
                    return;
                }
                let done = frame("speak", json!({"utterance_id":id,"text":text.as_str()}));
                if done.len() > MAX_MESSAGE_BYTES {
                    run.outcome = "exhausted";
                    out.send(frame(
                        "error",
                        json!({"message":"model output exceeded budget"}),
                    ));
                    return;
                }
                if out.send(done) {
                    run.outcome = "completed";
                }
            }
            Ok(Err(StreamError::Stopped)) => {}
            Ok(Err(StreamError::Exhausted)) => {
                run.outcome = "exhausted";
                out.send(frame(
                    "error",
                    json!({"message":"model output exceeded budget"}),
                ));
            }
            Ok(Err(StreamError::Transport | StreamError::Protocol)) => {
                run.outcome = "failed";
                out.send(frame("error", json!({"message":"model request failed"})));
            }
            Err(_) => {
                run.outcome = "exhausted";
                out.send(frame("error", json!({"message":"model request timed out"})));
            }
        }
    }))
}

/// Result of checking the configured adapter for diagnostics.
#[derive(Clone, Copy)]
enum AdapterStatus {
    Echo,
    Local,
    Unavailable(ModelUnavailable),
}

fn diagnostics(status: AdapterStatus, last_run: Option<RunRecord>) -> Value {
    let (mode, streaming, model) = match status {
        AdapterStatus::Echo => (
            "echo",
            "Bounded synthetic deltas; cancel closes this connection.",
            json!({"name":"Model adapter","status":"degraded","remedy":"Use Neura's primary chat or install a reviewed sidecar model adapter.","detail":"Safe local echo provider is active."}),
        ),
        AdapterStatus::Local => (
            "local",
            "Bounded local-model deltas; cancel closes this connection and aborts the model request.",
            json!({"name":"Model adapter","status":"ok","remedy":"None","detail":"Pinned local model verified on loopback Ollama; fixed synthetic prompts only."}),
        ),
        AdapterStatus::Unavailable(reason) => (
            "unavailable",
            "No model work is admitted while the adapter is unavailable.",
            json!({"name":"Model adapter","status":"unavailable","code":reason.code(),
                "remedy":"Start Ollama and install the pinned model yourself; Neura never downloads models or falls back to a cloud provider.",
                "detail":"The opted-in local model adapter could not be verified."}),
        ),
    };
    let mut data = json!({
        "generated_at": now_iso8601(),
        "input_scope":"synthetic-only",
        "model_mode": mode,
        "checks":[
            {"name":"WebSocket","status":"ok","remedy":"None","detail":"Authenticated loopback control channel connected."},
            {"name":"Streaming","status":"ok","remedy":"None","detail":streaming},
            model,
        ]
    });
    if !matches!(status, AdapterStatus::Echo) {
        data["model"] = json!({
            "tag": local_model::MODEL,
            "family": local_model::FAMILY,
            "parameter_size": local_model::PARAMETER_SIZE,
            "quantization": local_model::QUANTIZATION,
        });
        data["last_run"] = last_run.map_or(Value::Null, |run| {
            json!({"fixture":run.fixture,"outcome":run.outcome,"ttft_ms":run.ttft_ms,
                "total_ms":run.total_ms,"output_bytes":run.output_bytes})
        });
    }
    data
}

fn spawn_diagnostics(out: Outbound, local: Arc<LocalAdapter>) -> OwnedTask {
    OwnedTask(tokio::spawn(async move {
        let status = tokio::select! {
            biased;
            _ = out.session.revoked() => return,
            _ = out.ended() => return,
            result = local.probe() => match result {
                Ok(()) => AdapterStatus::Local,
                Err(reason) => AdapterStatus::Unavailable(reason),
            },
        };
        out.send(frame("diagnostics", diagnostics(status, local.last_run())));
    }))
}

fn spawn_echo(fixture: SyntheticFixture, out: Outbound) -> OwnedTask {
    OwnedTask(tokio::spawn(async move {
        let id = Uuid::new_v4().to_string();
        let response = match fixture {
            SyntheticFixture::Hello => "Local brain link is working. Synthetic input.".to_string(),
            SyntheticFixture::Stream => "Synthetic Neura engine test input. ".repeat(20),
        };
        for word in response.split_whitespace() {
            if !out.send(frame(
                "speak_delta",
                json!({"utterance_id":id,"delta":format!("{word} ")}),
            )) {
                return;
            }
            tokio::select! {
                biased;
                _ = out.session.revoked() => return,
                _ = out.ended() => return,
                _ = tokio::time::sleep(Duration::from_millis(55)) => {},
            }
        }
        out.send(frame("speak", json!({"utterance_id":id,"text":response})));
    }))
}

async fn client(socket: WebSocket, session: Session, adapter: Adapter) {
    // Recheck after the asynchronous HTTP upgrade, including revocation races.
    if !session.is_active() {
        return;
    }
    let (socket_tx, mut socket_rx) = socket.split();
    let (out, out_rx) = Outbound::new(session);
    let writer_out = out.clone();
    let writer = OwnedTask(tokio::spawn(write_outbound(socket_tx, out_rx, writer_out)));
    let mut generation: Option<OwnedTask> = None;
    let mut probe: Option<OwnedTask> = None;

    loop {
        let message = tokio::select! {
            biased;
            _ = out.session.revoked() => break,
            _ = out.ended() => break,
            message = socket_rx.next() => match message {
                Some(Ok(message)) => message,
                _ => break,
            },
        };
        if !out.is_active() {
            break;
        }
        let text = match message {
            Message::Text(text) => text,
            Message::Ping(_) | Message::Pong(_) => continue,
            _ => break,
        };
        let Ok(input) = serde_json::from_str::<InEnvelope>(&text) else {
            out.send(frame("error", json!({"message":"invalid envelope"})));
            continue;
        };

        match input.kind.as_str() {
            "hello" => {
                out.send(frame(
                    "hello",
                    json!({"service":"neura-api","version":"0.4.0","protocol_version":1,"input_scope":"synthetic-only","model_adapter":adapter.name()}),
                ));
            }
            "room_entered" => {
                let tone = match input.data.get("room").and_then(Value::as_str) {
                    Some("therapy") => "calm",
                    Some("focus" | "focus_office") => "focused",
                    Some("care") => "hopeful",
                    _ => "warm",
                };
                out.send(frame("set_tone", json!({"tone":tone})));
            }
            "diagnostics_request" => match &adapter {
                Adapter::Echo => {
                    out.send(frame("diagnostics", diagnostics(AdapterStatus::Echo, None)));
                }
                Adapter::Local(local) => {
                    if probe.as_ref().is_some_and(|task| !task.0.is_finished()) {
                        out.send(frame(
                            "error",
                            json!({"message":"diagnostics already active"}),
                        ));
                        continue;
                    }
                    probe = Some(spawn_diagnostics(out.clone(), local.clone()));
                }
            },
            "synthetic_input" => {
                if generation
                    .as_ref()
                    .is_some_and(|task| !task.0.is_finished())
                {
                    out.send(frame(
                        "error",
                        json!({"message":"synthetic work already active"}),
                    ));
                    continue;
                }
                match serde_json::from_value::<SyntheticInput>(input.data) {
                    Ok(input) => {
                        generation = Some(match &adapter {
                            Adapter::Echo => spawn_echo(input.fixture, out.clone()),
                            Adapter::Local(local) => {
                                spawn_local(input.fixture, out.clone(), local.clone())
                            }
                        })
                    }
                    Err(_) => {
                        out.send(frame(
                            "error",
                            json!({"message":"expected a known synthetic fixture only"}),
                        ));
                    }
                }
            }
            "cancel" => break,
            _ => {
                // Never log an untrusted kind, envelope, prompt or credential.
                out.send(frame(
                    "error",
                    json!({"message":"unsupported event; synthetic inputs only"}),
                ));
            }
        }
    }

    out.stop();
    if let Some(task) = generation {
        task.stop().await;
    }
    if let Some(task) = probe {
        task.stop().await;
    }
    writer.stop().await;
}

fn now_iso8601() -> String {
    // This remains a content-free Unix-millisecond health timestamp.
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .to_string()
}

// Fixed echo fixtures and the single loopback model request need one scheduler
// thread, independent of CPU count.
#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        // Do not let RUST_LOG enable dependency wire/header/body tracing.
        .with_env_filter(tracing_subscriber::EnvFilter::new("neura_api=info"))
        .with_writer(std::io::stderr)
        .init();
    let address = std::env::var("NEURA_API_ADDR").unwrap_or_else(|_| "127.0.0.1:8787".into());
    // Both settings fail closed. Environment errors never include their values.
    local_address(&address)?;
    let token = std::env::var("NEURA_API_SESSION_TOKEN")
        .map_err(|_| "NEURA_API_SESSION_TOKEN is required for an explicit synthetic session")?;
    let session = Session::new(token)?;
    // Absent means the default echo adapter. Any other value than the two
    // supported names fails closed; the value itself is never logged.
    let adapter = match std::env::var(MODEL_ADAPTER_ENV) {
        Ok(value) => Adapter::from_setting(Some(&value))?,
        Err(std::env::VarError::NotPresent) => Adapter::Echo,
        Err(_) => Adapter::from_setting(Some(""))?,
    };
    let listener = bind_local(&address).await?;
    let address = listener.local_addr()?;
    // Only a trusted child pipe carries this bounded, credential-free startup
    // receipt. Publish it after binding; a failed bind cannot authenticate the
    // launcher to an unrelated listener. Ordinary standalone startup is quiet.
    if std::env::var("NEURA_API_LAUNCHER_READY").as_deref() == Ok("1") {
        use std::io::Write;
        writeln!(std::io::stdout(), "NEURA_IPC_READY {address}")?;
        std::io::stdout().flush()?;
    }
    info!(%address, adapter = adapter.name(), "Neura synthetic local brain listening");
    axum::serve(
        listener,
        app_with(session, adapter).into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;
    Ok(())
}

#[cfg(test)]
#[path = "../ipc_tests.rs"]
mod tests;
