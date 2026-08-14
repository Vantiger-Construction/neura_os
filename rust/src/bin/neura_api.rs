use axum::{
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    response::Response,
    routing::get,
    Router,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{net::SocketAddr, time::Duration};
use tokio::{net::TcpListener, task::JoinHandle};
use tracing::{info, warn};
use uuid::Uuid;

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
        v: 1,
        kind,
        id: Uuid::new_v4().to_string(),
        data,
    })
    .expect("serialize envelope")
}

async fn ws_handler(ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(client)
}

async fn client(socket: WebSocket) {
    let (mut socket_tx, mut socket_rx) = socket.split();
    let (out_tx, mut out_rx) = tokio::sync::mpsc::unbounded_channel::<String>();

    let writer = tokio::spawn(async move {
        while let Some(text) = out_rx.recv().await {
            if socket_tx.send(Message::Text(text)).await.is_err() {
                break;
            }
        }
    });

    let mut generation: Option<(JoinHandle<()>, String)> = None;

    while let Some(Ok(message)) = socket_rx.next().await {
        let Message::Text(text) = message else {
            continue;
        };
        let Ok(input) = serde_json::from_str::<InEnvelope>(&text) else {
            let _ = out_tx.send(frame("error", json!({"message":"invalid envelope"})));
            continue;
        };

        match input.kind.as_str() {
            "hello" => {
                let _ = out_tx.send(frame(
                    "hello",
                    json!({"service":"neura-api","version":"0.2.0","protocol_version":1}),
                ));
            }
            "room_entered" => {
                let room = input
                    .data
                    .get("room")
                    .and_then(Value::as_str)
                    .unwrap_or("penthouse");
                let tone = match room {
                    "therapy" => "calm",
                    "focus" | "focus_office" => "focused",
                    "care" => "hopeful",
                    _ => "warm",
                };
                let _ = out_tx.send(frame("set_tone", json!({"tone":tone})));
            }
            "diagnostics_request" => {
                let _ = out_tx.send(frame(
                    "diagnostics",
                    json!({
                        "generated_at": now_iso8601(),
                        "checks":[
                            {"name":"WebSocket","status":"ok","remedy":"None","detail":"Local control channel connected."},
                            {"name":"Streaming","status":"ok","remedy":"None","detail":"Delta and interruption events enabled."},
                            {"name":"Model adapter","status":"degraded","remedy":"Use Neura's primary chat or install a reviewed sidecar model adapter.","detail":"Safe local echo provider is active."}
                        ]
                    }),
                ));
            }
            "user_text" => {
                if let Some((old_task, old_id)) = generation.take() {
                    if !old_task.is_finished() {
                        old_task.abort();
                        let _ = out_tx.send(frame(
                            "speak_interrupted",
                            json!({"utterance_id":old_id}),
                        ));
                    }
                }

                let utterance_id = input
                    .data
                    .get("utterance_id")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
                    .to_string();
                let prompt = input
                    .data
                    .get("text")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .trim()
                    .to_string();

                let stream_tx = out_tx.clone();
                let id = utterance_id.clone();
                let task = tokio::spawn(async move {
                    let response = if prompt.is_empty() {
                        "I didn't receive any text.".to_string()
                    } else {
                        format!("Local brain link is working. You said: {prompt}")
                    };
                    for word in response.split_whitespace() {
                        let _ = stream_tx.send(frame(
                            "speak_delta",
                            json!({"utterance_id":id,"delta":format!("{word} ")}),
                        ));
                        tokio::time::sleep(Duration::from_millis(55)).await;
                    }
                    let _ = stream_tx.send(frame(
                        "speak",
                        json!({"utterance_id":id,"text":response}),
                    ));
                });
                generation = Some((task, utterance_id));
            }
            other => warn!(kind = other, "unsupported inbound event"),
        }
    }

    if let Some((task, _)) = generation {
        task.abort();
    }
    writer.abort();
}

fn now_iso8601() -> String {
    // An absolute monotonic timestamp is unnecessary for health display; this
    // remains dependency-free and unambiguous as Unix milliseconds.
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    millis.to_string()
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
    let listener = TcpListener::bind(address)
        .await
        .expect("bind Neura local brain");
    info!(%address, "Neura local brain listening");
    axum::serve(listener, Router::new().route("/", get(ws_handler)))
        .await
        .expect("serve Neura local brain");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_has_frozen_contract() {
        let value: Value = serde_json::from_str(&frame("diagnostics", json!({}))).unwrap();
        assert_eq!(value["v"], 1);
        assert_eq!(value["kind"], "diagnostics");
        assert!(value["id"].as_str().is_some_and(|id| !id.is_empty()));
        assert!(value["data"].is_object());
    }
}
