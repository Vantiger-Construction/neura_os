use axum::{
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    http::{header::ORIGIN, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    net::SocketAddr,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{net::TcpListener, sync::mpsc, task::JoinHandle};
use tracing::{info, warn};
use uuid::Uuid;

const PROTOCOL_VERSION: u32 = 1;
const SERVICE_VERSION: &str = "0.3.0";
/// Largest WebSocket message the server will accept from a client.
const MAX_FRAME_BYTES: usize = 64 * 1024;
/// Largest `user_text.text` (in characters) the brain will answer.
const MAX_TEXT_CHARS: usize = 8_000;
const MAX_ID_CHARS: usize = 128;
/// Bounded so a stalled client applies backpressure instead of growing memory.
const OUTBOUND_QUEUE: usize = 256;

#[derive(Debug, Deserialize)]
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
        v: PROTOCOL_VERSION,
        kind,
        id: Uuid::new_v4().to_string(),
        data,
    })
    .expect("serialize envelope")
}

fn error_frame(code: &str, message: &str) -> String {
    frame("error", json!({"code": code, "message": message}))
}

/// Maps the app's current room ids (and the legacy names older builds sent)
/// to a tone name understood by the Dart `NeuraTone` enum.
fn tone_for_room(room: &str) -> &'static str {
    match room {
        "reflection_bay" | "dream_atrium" | "therapy" => "calm",
        "penthouse" | "focus" | "focus_office" => "focused",
        "joy_lounge" | "care" => "hopeful",
        _ => "warm",
    }
}

/// Browsers attach an `Origin` header to WebSocket handshakes; the native app
/// does not. Refusing any Origin stops web pages from driving the local brain
/// through the user's loopback interface.
fn origin_allowed(headers: &HeaderMap) -> bool {
    !headers.contains_key(ORIGIN)
}

/// The brain is a same-device service. Anything but loopback must be an
/// explicit, deliberate opt-in.
fn check_bind(address: &SocketAddr, allow_non_loopback: bool) -> Result<(), String> {
    if address.ip().is_loopback() || allow_non_loopback {
        Ok(())
    } else {
        Err(format!(
            "refusing to listen on non-loopback address {address}; \
             set NEURA_API_ALLOW_NONLOOPBACK=1 to override"
        ))
    }
}

/// Validated `user_text` payload.
#[derive(Debug, PartialEq)]
struct UserText {
    utterance_id: String,
    prompt: String,
}

fn parse_user_text(data: &Value) -> Result<UserText, (&'static str, &'static str)> {
    let utterance_id = match data.get("utterance_id") {
        None | Some(Value::Null) => Uuid::new_v4().to_string(),
        Some(Value::String(id)) if !id.is_empty() && id.chars().count() <= MAX_ID_CHARS => {
            id.clone()
        }
        Some(_) => {
            return Err((
                "invalid_utterance_id",
                "utterance_id must be a short string",
            ))
        }
    };
    let prompt = match data.get("text") {
        None | Some(Value::Null) => "",
        Some(Value::String(text)) => text.trim(),
        Some(_) => return Err(("invalid_text", "text must be a string")),
    };
    if prompt.chars().count() > MAX_TEXT_CHARS {
        return Err(("text_too_long", "text exceeds the maximum length"));
    }
    Ok(UserText {
        utterance_id,
        prompt: prompt.to_string(),
    })
}

/// Unix time as an RFC 3339 UTC timestamp with millisecond precision, which is
/// what the app's `DateTime.tryParse` expects.
fn rfc3339_utc(unix_millis: u64) -> String {
    let secs = unix_millis / 1000;
    let millis = unix_millis % 1000;
    let days = (secs / 86_400) as i64;
    let rem = secs % 86_400;
    // Civil-from-days (H. Hinnant), proleptic Gregorian calendar.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{millis:03}Z",
        rem / 3_600,
        rem % 3_600 / 60,
        rem % 60
    )
}

fn now_iso8601() -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    rfc3339_utc(millis as u64)
}

async fn health() -> Json<Value> {
    Json(json!({
        "service": "neura-api",
        "version": SERVICE_VERSION,
        "protocol_version": PROTOCOL_VERSION,
        "status": "ready",
    }))
}

async fn ws_handler(headers: HeaderMap, ws: WebSocketUpgrade) -> Response {
    if !origin_allowed(&headers) {
        return (StatusCode::FORBIDDEN, "browser origins are not allowed").into_response();
    }
    ws.max_message_size(MAX_FRAME_BYTES)
        .max_frame_size(MAX_FRAME_BYTES)
        .on_upgrade(client)
}

fn app() -> Router {
    Router::new()
        .route("/", get(ws_handler))
        .route("/health", get(health))
}

/// Queues a frame; `false` means the client is gone and the caller should stop.
async fn emit(tx: &mpsc::Sender<String>, text: String) -> bool {
    tx.send(text).await.is_ok()
}

async fn interrupt(generation: &mut Option<(JoinHandle<()>, String)>, tx: &mpsc::Sender<String>) {
    if let Some((task, id)) = generation.take() {
        if !task.is_finished() {
            task.abort();
            let _ = emit(tx, frame("speak_interrupted", json!({"utterance_id": id}))).await;
        }
    }
}

async fn client(socket: WebSocket) {
    let (mut socket_tx, mut socket_rx) = socket.split();
    let (out_tx, mut out_rx) = mpsc::channel::<String>(OUTBOUND_QUEUE);

    let writer = tokio::spawn(async move {
        while let Some(text) = out_rx.recv().await {
            if socket_tx.send(Message::Text(text)).await.is_err() {
                break;
            }
        }
    });

    let mut generation: Option<(JoinHandle<()>, String)> = None;

    while let Some(Ok(message)) = socket_rx.next().await {
        let text = match message {
            Message::Text(text) => text,
            Message::Close(_) => break,
            Message::Binary(_) => {
                let _ = emit(
                    &out_tx,
                    error_frame("binary_unsupported", "only text frames are supported"),
                )
                .await;
                continue;
            }
            _ => continue,
        };
        let Ok(input) = serde_json::from_str::<InEnvelope>(&text) else {
            let _ = emit(&out_tx, error_frame("invalid_envelope", "invalid envelope")).await;
            continue;
        };

        let alive = match input.kind.as_str() {
            "hello" => {
                emit(
                    &out_tx,
                    frame(
                        "hello",
                        json!({
                            "service": "neura-api",
                            "version": SERVICE_VERSION,
                            "protocol_version": PROTOCOL_VERSION,
                            "capabilities": ["stream", "interrupt", "diagnostics"],
                            "limits": {
                                "max_text_chars": MAX_TEXT_CHARS,
                                "max_frame_bytes": MAX_FRAME_BYTES,
                            },
                        }),
                    ),
                )
                .await
            }
            "room_entered" => {
                let room = input
                    .data
                    .get("room")
                    .and_then(Value::as_str)
                    .unwrap_or("penthouse");
                emit(
                    &out_tx,
                    frame("set_tone", json!({"tone": tone_for_room(room)})),
                )
                .await
            }
            "diagnostics_request" => {
                let streaming = generation.as_ref().is_some_and(|(t, _)| !t.is_finished());
                emit(
                    &out_tx,
                    frame(
                        "diagnostics",
                        json!({
                            "generated_at": now_iso8601(),
                            "checks": [
                                {"name":"WebSocket","status":"ok","remedy":"None","detail":"Local control channel connected."},
                                {"name":"Streaming","status":"ok","remedy":"None","detail": if streaming {"A reply is currently streaming."} else {"Delta and interruption events enabled."}},
                                {"name":"Model adapter","status":"degraded","remedy":"Use Neura's primary chat or install a reviewed sidecar model adapter.","detail":"Safe local echo provider is active."}
                            ]
                        }),
                    ),
                )
                .await
            }
            "interrupt" => {
                interrupt(&mut generation, &out_tx).await;
                true
            }
            "user_text" => match parse_user_text(&input.data) {
                Err((code, message)) => emit(&out_tx, error_frame(code, message)).await,
                Ok(UserText {
                    utterance_id,
                    prompt,
                }) => {
                    interrupt(&mut generation, &out_tx).await;

                    let stream_tx = out_tx.clone();
                    let id = utterance_id.clone();
                    let task = tokio::spawn(async move {
                        let response = if prompt.is_empty() {
                            "I didn't receive any text.".to_string()
                        } else {
                            format!("Local brain link is working. You said: {prompt}")
                        };
                        for word in response.split_whitespace() {
                            let delta = frame(
                                "speak_delta",
                                json!({"utterance_id": id, "delta": format!("{word} ")}),
                            );
                            if !emit(&stream_tx, delta).await {
                                return;
                            }
                            tokio::time::sleep(Duration::from_millis(55)).await;
                        }
                        let _ = emit(
                            &stream_tx,
                            frame("speak", json!({"utterance_id": id, "text": response})),
                        )
                        .await;
                    });
                    generation = Some((task, utterance_id));
                    true
                }
            },
            other => {
                warn!(kind = other, "unsupported inbound event");
                emit(
                    &out_tx,
                    error_frame("unsupported_kind", "unsupported event kind"),
                )
                .await
            }
        };
        if !alive {
            break;
        }
    }

    if let Some((task, _)) = generation {
        task.abort();
    }
    writer.abort();
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    let address: SocketAddr = std::env::var("NEURA_API_ADDR")
        .unwrap_or_else(|_| "127.0.0.1:8787".into())
        .parse()
        .expect("valid NEURA_API_ADDR");
    let allow_non_loopback = std::env::var("NEURA_API_ALLOW_NONLOOPBACK").as_deref() == Ok("1");
    if let Err(message) = check_bind(&address, allow_non_loopback) {
        eprintln!("{message}");
        std::process::exit(2);
    }
    let listener = TcpListener::bind(address)
        .await
        .expect("bind Neura local brain");
    info!(%address, "Neura local brain listening");
    axum::serve(listener, app())
        .await
        .expect("serve Neura local brain");
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[test]
    fn envelope_has_frozen_contract() {
        let value: Value = serde_json::from_str(&frame("diagnostics", json!({}))).unwrap();
        assert_eq!(value["v"], 1);
        assert_eq!(value["kind"], "diagnostics");
        assert!(value["id"].as_str().is_some_and(|id| !id.is_empty()));
        assert!(value["data"].is_object());
    }

    #[test]
    fn timestamp_is_rfc3339_utc() {
        assert_eq!(rfc3339_utc(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(rfc3339_utc(1_700_000_000_123), "2023-11-14T22:13:20.123Z");
        // Leap day, and the day after it.
        assert_eq!(rfc3339_utc(951_782_400_000), "2000-02-29T00:00:00.000Z");
        assert_eq!(rfc3339_utc(951_868_800_000), "2000-03-01T00:00:00.000Z");
        assert_eq!(rfc3339_utc(4_102_444_799_999), "2099-12-31T23:59:59.999Z");
    }

    #[test]
    fn current_app_rooms_map_to_app_tones() {
        for room in [
            "penthouse",
            "reflection_bay",
            "joy_lounge",
            "mood_den",
            "dream_atrium",
            "legacy_vault",
        ] {
            assert!(
                ["calm", "warm", "focused", "hopeful"].contains(&tone_for_room(room)),
                "{room}"
            );
        }
        assert_eq!(tone_for_room("reflection_bay"), "calm");
        assert_eq!(tone_for_room("penthouse"), "focused");
        assert_eq!(tone_for_room("legacy"), "warm");
    }

    #[test]
    fn browser_origins_are_rejected() {
        let mut headers = HeaderMap::new();
        assert!(origin_allowed(&headers));
        headers.insert(ORIGIN, "https://example.com".parse().unwrap());
        assert!(!origin_allowed(&headers));
    }

    #[test]
    fn non_loopback_bind_requires_opt_in() {
        let lan: SocketAddr = "0.0.0.0:8787".parse().unwrap();
        let local: SocketAddr = "127.0.0.1:8787".parse().unwrap();
        let v6: SocketAddr = "[::1]:8787".parse().unwrap();
        assert!(check_bind(&local, false).is_ok());
        assert!(check_bind(&v6, false).is_ok());
        assert!(check_bind(&lan, false).is_err());
        assert!(check_bind(&lan, true).is_ok());
    }

    #[test]
    fn user_text_is_validated() {
        let ok = parse_user_text(&json!({"utterance_id":"u1","text":"  hi  "})).unwrap();
        assert_eq!(ok.utterance_id, "u1");
        assert_eq!(ok.prompt, "hi");

        let generated = parse_user_text(&json!({"text":"hi"})).unwrap();
        assert!(!generated.utterance_id.is_empty());
        assert_ne!(generated.utterance_id, "unknown");

        assert_eq!(parse_user_text(&json!({})).unwrap().prompt, "");
        assert!(parse_user_text(&json!({"text": 5})).is_err());
        assert!(parse_user_text(&json!({"utterance_id": ""})).is_err());
        assert!(parse_user_text(&json!({"utterance_id": "x".repeat(MAX_ID_CHARS + 1)})).is_err());
        let long = "a".repeat(MAX_TEXT_CHARS + 1);
        assert_eq!(
            parse_user_text(&json!({"text": long})).unwrap_err().0,
            "text_too_long"
        );
        let max = "a".repeat(MAX_TEXT_CHARS);
        assert!(parse_user_text(&json!({"text": max})).is_ok());
    }

    /// Sends one raw HTTP request to a real in-process server and returns the
    /// full response text.
    async fn raw_request(request: &str) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app()).await.unwrap();
        });
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        stream.write_all(request.as_bytes()).await.unwrap();
        let mut response = Vec::new();
        let _ =
            tokio::time::timeout(Duration::from_secs(3), stream.read_to_end(&mut response)).await;
        String::from_utf8_lossy(&response).into_owned()
    }

    #[tokio::test]
    async fn health_endpoint_reports_ready() {
        let response =
            raw_request("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
                .await;
        assert!(response.starts_with("HTTP/1.1 200"), "{response}");
        assert!(response.contains("\"status\":\"ready\""), "{response}");
    }

    #[tokio::test]
    async fn websocket_handshake_with_browser_origin_is_forbidden() {
        let response = raw_request(
            "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\
             Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\
             Origin: https://evil.example\r\n\r\n",
        )
        .await;
        assert!(response.starts_with("HTTP/1.1 403"), "{response}");
    }

    #[tokio::test]
    async fn websocket_handshake_without_origin_upgrades() {
        let response = raw_request(
            "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\
             Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n",
        )
        .await;
        assert!(response.starts_with("HTTP/1.1 101"), "{response}");
    }
}
