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
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{net::SocketAddr, sync::Arc, time::Duration};
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

fn app(session: Session) -> Router {
    Router::new()
        .route("/", get(ws_handler))
        .route("/session/revoke", post(revoke_session))
        .with_state(session)
}

async fn ws_handler(
    State(session): State<Session>,
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
            client(socket, session).await;
        }))
}

async fn revoke_session(
    State(session): State<Session>,
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

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum SyntheticFixture {
    Hello,
    Stream,
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

async fn client(socket: WebSocket, session: Session) {
    // Recheck after the asynchronous HTTP upgrade, including revocation races.
    if !session.is_active() {
        return;
    }
    let (socket_tx, mut socket_rx) = socket.split();
    let (out, out_rx) = Outbound::new(session);
    let writer_out = out.clone();
    let writer = OwnedTask(tokio::spawn(write_outbound(socket_tx, out_rx, writer_out)));
    let mut generation: Option<OwnedTask> = None;

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
                    json!({"service":"neura-api","version":"0.3.0","protocol_version":1,"input_scope":"synthetic-only"}),
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
            "diagnostics_request" => {
                out.send(frame(
                    "diagnostics",
                    json!({
                        "generated_at": now_iso8601(),
                        "input_scope":"synthetic-only",
                        "checks":[
                            {"name":"WebSocket","status":"ok","remedy":"None","detail":"Authenticated loopback control channel connected."},
                            {"name":"Streaming","status":"ok","remedy":"None","detail":"Bounded synthetic deltas; cancel closes this connection."},
                            {"name":"Model adapter","status":"degraded","remedy":"Use Neura's primary chat or install a reviewed sidecar model adapter.","detail":"Safe local echo provider is active."}
                        ]
                    }),
                ));
            }
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
                    Ok(input) => generation = Some(spawn_echo(input.fixture, out.clone())),
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

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        // Do not let RUST_LOG enable dependency wire/header/body tracing.
        .with_env_filter(tracing_subscriber::EnvFilter::new("neura_api=info"))
        .init();
    let address = std::env::var("NEURA_API_ADDR").unwrap_or_else(|_| "127.0.0.1:8787".into());
    // Both settings fail closed. Environment errors never include their values.
    local_address(&address)?;
    let token = std::env::var("NEURA_API_SESSION_TOKEN")
        .map_err(|_| "NEURA_API_SESSION_TOKEN is required for an explicit synthetic session")?;
    let session = Session::new(token)?;
    let listener = bind_local(&address).await?;
    let address = listener.local_addr()?;
    info!(%address, "Neura synthetic local brain listening");
    axum::serve(
        listener,
        app(session).into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;
    Ok(())
}

#[cfg(test)]
#[path = "../ipc_tests.rs"]
mod tests;
