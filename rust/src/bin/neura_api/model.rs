//! Model adapters for the local brain.
//!
//! The default adapter talks to an Ollama server on this device. Nothing here
//! calls a cloud service: the Ollama URL must be loopback unless the operator
//! sets `NEURA_API_ALLOW_NONLOOPBACK=1`, the same switch that guards the
//! listener. When no local model is available the brain falls back to a safe
//! echo provider so the console keeps working.

use std::{net::IpAddr, time::Duration};

use reqwest::Url;
use serde_json::{json, Value};
use tokio::sync::mpsc;

pub const DEFAULT_OLLAMA_URL: &str = "http://127.0.0.1:11434";
/// Turns kept per connection (user + assistant messages).
pub const MAX_HISTORY_TURNS: usize = 20;
const MAX_REPLY_CHARS: usize = 16_000;
const MAX_REPLY_TOKENS: u32 = 1_024;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(3);
const PROBE_TIMEOUT: Duration = Duration::from_millis(1_500);
/// Generous because the first chunk includes loading the model into memory.
const CHUNK_TIMEOUT: Duration = Duration::from_secs(120);
const ECHO_WORD_DELAY: Duration = Duration::from_millis(55);
const SYSTEM_PROMPT: &str = "You are Neura, a warm, concise personal companion running \
locally on the user's device. Keep replies short and clear. Never claim abilities you \
do not have.";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// Use Ollama when reachable, otherwise echo.
    Auto,
    /// Require Ollama; report an error instead of falling back.
    Ollama,
    Echo,
}

#[derive(Clone, Debug)]
pub struct ModelConfig {
    pub mode: Mode,
    pub ollama_url: Url,
    /// `None` means "use the first installed model".
    pub ollama_model: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ChatTurn {
    pub role: &'static str,
    pub content: String,
}

impl ChatTurn {
    pub fn user(content: impl Into<String>) -> Self {
        Self {
            role: "user",
            content: content.into(),
        }
    }
    pub fn assistant(content: impl Into<String>) -> Self {
        Self {
            role: "assistant",
            content: content.into(),
        }
    }
}

/// Appends `turn` and drops the oldest turns beyond [`MAX_HISTORY_TURNS`].
pub fn push_turn(history: &mut Vec<ChatTurn>, turn: ChatTurn) {
    history.push(turn);
    if history.len() > MAX_HISTORY_TURNS {
        let excess = history.len() - MAX_HISTORY_TURNS;
        history.drain(..excess);
    }
}

fn validated_url(raw: &str, allow_non_loopback: bool) -> Result<Url, String> {
    let url = Url::parse(raw).map_err(|e| format!("invalid NEURA_OLLAMA_URL: {e}"))?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err("NEURA_OLLAMA_URL must be http or https".into());
    }
    let host = url.host_str().ok_or("NEURA_OLLAMA_URL needs a host")?;
    let local = host.eq_ignore_ascii_case("localhost")
        || host
            .trim_matches(|c| c == '[' || c == ']')
            .parse::<IpAddr>()
            .is_ok_and(|ip| ip.is_loopback());
    if local || allow_non_loopback {
        Ok(url)
    } else {
        Err(format!(
            "refusing non-loopback NEURA_OLLAMA_URL host {host}; \
             set NEURA_API_ALLOW_NONLOOPBACK=1 to override"
        ))
    }
}

impl ModelConfig {
    /// `NEURA_MODEL_ADAPTER` = `auto` (default) | `ollama` | `echo`,
    /// `NEURA_OLLAMA_URL`, `NEURA_OLLAMA_MODEL`.
    pub fn from_values(
        adapter: Option<&str>,
        url: Option<&str>,
        model: Option<&str>,
        allow_non_loopback: bool,
    ) -> Result<Self, String> {
        let mode = match adapter.map(str::trim).filter(|v| !v.is_empty()) {
            None => Mode::Auto,
            Some(v) if v.eq_ignore_ascii_case("auto") => Mode::Auto,
            Some(v) if v.eq_ignore_ascii_case("ollama") => Mode::Ollama,
            Some(v) if v.eq_ignore_ascii_case("echo") => Mode::Echo,
            Some(v) => {
                return Err(format!(
                    "unknown NEURA_MODEL_ADAPTER '{v}' (use auto, ollama or echo)"
                ))
            }
        };
        Ok(Self {
            mode,
            ollama_url: validated_url(url.unwrap_or(DEFAULT_OLLAMA_URL), allow_non_loopback)?,
            ollama_model: model
                .map(str::trim)
                .filter(|m| !m.is_empty())
                .map(str::to_string),
        })
    }

    pub fn from_env(allow_non_loopback: bool) -> Result<Self, String> {
        let get = |key: &str| std::env::var(key).ok();
        Self::from_values(
            get("NEURA_MODEL_ADAPTER").as_deref(),
            get("NEURA_OLLAMA_URL").as_deref(),
            get("NEURA_OLLAMA_MODEL").as_deref(),
            allow_non_loopback,
        )
    }

    fn endpoint(&self, path: &str) -> Url {
        let mut url = self.ollama_url.clone();
        url.set_path(path);
        url
    }
}

/// One NDJSON line from Ollama's `/api/chat`. `Ok((delta, done))`, or the
/// server's error string.
fn parse_chat_line(line: &str) -> Result<(String, bool), String> {
    let value: Value =
        serde_json::from_str(line).map_err(|e| format!("unreadable model stream: {e}"))?;
    if let Some(error) = value.get("error").and_then(Value::as_str) {
        return Err(error.to_string());
    }
    let delta = value
        .pointer("/message/content")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let done = value.get("done").and_then(Value::as_bool).unwrap_or(false);
    Ok((delta, done))
}

fn client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .redirect(reqwest::redirect::Policy::none())
        .no_proxy()
        .build()
        .map_err(|e| e.to_string())
}

/// Picks the model to use: the configured one if installed, else the first
/// installed model. `Err` explains what to fix.
pub async fn resolve_model(cfg: &ModelConfig) -> Result<String, String> {
    let response = client()?
        .get(cfg.endpoint("/api/tags"))
        .timeout(PROBE_TIMEOUT)
        .send()
        .await
        .map_err(|_| "Ollama is not reachable. Start it with `ollama serve`.".to_string())?;
    if !response.status().is_success() {
        return Err(format!("Ollama answered HTTP {}.", response.status()));
    }
    let body: Value = response
        .json()
        .await
        .map_err(|_| "Ollama returned an unreadable model list.".to_string())?;
    let installed: Vec<&str> = body
        .get("models")
        .and_then(Value::as_array)
        .map(|models| {
            models
                .iter()
                .filter_map(|m| m.get("name").and_then(Value::as_str))
                .collect()
        })
        .unwrap_or_default();
    match &cfg.ollama_model {
        Some(wanted) if installed.contains(&wanted.as_str()) => Ok(wanted.clone()),
        Some(wanted) => Err(format!(
            "Model '{wanted}' is not installed. Run `ollama pull {wanted}`."
        )),
        None => installed
            .first()
            .map(|m| m.to_string())
            .ok_or_else(|| "No Ollama model is installed. Run `ollama pull llama3.2`.".to_string()),
    }
}

/// Diagnostics entry for the model adapter: `(status, detail, remedy)`.
pub async fn diagnostics(cfg: &ModelConfig) -> (&'static str, String, String) {
    if cfg.mode == Mode::Echo {
        return (
            "degraded",
            "Safe local echo provider is active.".into(),
            "Set NEURA_MODEL_ADAPTER=auto to use a local Ollama model.".into(),
        );
    }
    match resolve_model(cfg).await {
        Ok(model) => (
            "ok",
            format!("Local Ollama model '{model}' is answering."),
            "None".into(),
        ),
        Err(problem) if cfg.mode == Mode::Auto => (
            "degraded",
            format!("Falling back to the safe local echo provider. {problem}"),
            problem,
        ),
        Err(problem) => ("error", problem.clone(), problem),
    }
}

/// Result of one generation. `error` is `(code, message)`; `text` is whatever
/// was produced (possibly partial).
pub struct Generation {
    pub text: String,
    pub error: Option<(&'static str, String)>,
}

/// Streams a reply to `history` into `deltas` and returns the full text.
pub async fn generate(
    cfg: &ModelConfig,
    history: &[ChatTurn],
    deltas: mpsc::Sender<String>,
) -> Generation {
    if cfg.mode != Mode::Echo {
        match resolve_model(cfg).await {
            Ok(model) => {
                let generation = stream_ollama(cfg, &model, history, &deltas).await;
                // Fall back only if nothing reached the user yet.
                if generation.error.is_none()
                    || !generation.text.is_empty()
                    || cfg.mode == Mode::Ollama
                {
                    return generation;
                }
            }
            Err(problem) if cfg.mode == Mode::Ollama => {
                return Generation {
                    text: String::new(),
                    error: Some(("model_unavailable", problem)),
                };
            }
            Err(_) => {}
        }
    }
    let prompt = history
        .iter()
        .rev()
        .find(|t| t.role == "user")
        .map(|t| t.content.as_str())
        .unwrap_or("");
    stream_echo(prompt, &deltas).await
}

async fn stream_echo(prompt: &str, deltas: &mpsc::Sender<String>) -> Generation {
    let text = if prompt.is_empty() {
        "I didn't receive any text.".to_string()
    } else {
        format!("Local brain link is working. You said: {prompt}")
    };
    for word in text.split_whitespace() {
        if deltas.send(format!("{word} ")).await.is_err() {
            break;
        }
        tokio::time::sleep(ECHO_WORD_DELAY).await;
    }
    Generation { text, error: None }
}

async fn stream_ollama(
    cfg: &ModelConfig,
    model: &str,
    history: &[ChatTurn],
    deltas: &mpsc::Sender<String>,
) -> Generation {
    let fail = |text: String, message: String| Generation {
        text,
        error: Some(("model_error", message)),
    };
    let mut messages = vec![json!({"role": "system", "content": SYSTEM_PROMPT})];
    messages.extend(
        history
            .iter()
            .map(|t| json!({"role": t.role, "content": t.content})),
    );
    let body = json!({
        "model": model,
        "messages": messages,
        "stream": true,
        "options": {"num_predict": MAX_REPLY_TOKENS},
    });
    let client = match client() {
        Ok(client) => client,
        Err(e) => return fail(String::new(), e),
    };
    let mut response = match client
        .post(cfg.endpoint("/api/chat"))
        .json(&body)
        .send()
        .await
    {
        Ok(response) => response,
        Err(_) => return fail(String::new(), "Ollama is not reachable.".into()),
    };
    if !response.status().is_success() {
        return fail(
            String::new(),
            format!("Ollama answered HTTP {}.", response.status()),
        );
    }

    let mut text = String::new();
    let mut pending: Vec<u8> = Vec::new();
    loop {
        let chunk = match tokio::time::timeout(CHUNK_TIMEOUT, response.chunk()).await {
            Err(_) => return fail(text, "The local model stopped responding.".into()),
            Ok(Err(_)) => return fail(text, "The connection to Ollama was lost.".into()),
            Ok(Ok(chunk)) => chunk,
        };
        let finished_stream = chunk.is_none();
        if let Some(bytes) = chunk {
            pending.extend_from_slice(&bytes);
        }
        let mut lines: Vec<Vec<u8>> = Vec::new();
        while let Some(pos) = pending.iter().position(|b| *b == b'\n') {
            lines.push(pending.drain(..=pos).collect());
        }
        if finished_stream && !pending.is_empty() {
            lines.push(std::mem::take(&mut pending));
        }
        for line in lines {
            match consume_line(&line, &mut text, deltas).await {
                LineOutcome::Continue => {}
                LineOutcome::Stop => return Generation { text, error: None },
                LineOutcome::Failed(message) => return fail(text, message),
            }
        }
        if finished_stream {
            return if text.is_empty() {
                fail(text, "The local model returned no text.".into())
            } else {
                Generation { text, error: None }
            };
        }
    }
}

enum LineOutcome {
    Continue,
    /// The reply is complete (or the listener went away).
    Stop,
    Failed(String),
}

async fn consume_line(
    line: &[u8],
    text: &mut String,
    deltas: &mpsc::Sender<String>,
) -> LineOutcome {
    let line = String::from_utf8_lossy(line);
    if line.trim().is_empty() {
        return LineOutcome::Continue;
    }
    match parse_chat_line(&line) {
        Err(message) => LineOutcome::Failed(message),
        Ok((delta, done)) => {
            if !delta.is_empty() {
                text.push_str(&delta);
                if deltas.send(delta).await.is_err() {
                    return LineOutcome::Stop;
                }
            }
            if done || text.chars().count() >= MAX_REPLY_CHARS {
                LineOutcome::Stop
            } else {
                LineOutcome::Continue
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        extract::Json as JsonBody,
        http::{header, StatusCode},
        response::IntoResponse,
        routing::{get, post},
        Router,
    };

    fn cfg(mode: Mode, url: &str, model: Option<&str>) -> ModelConfig {
        ModelConfig::from_values(
            Some(match mode {
                Mode::Auto => "auto",
                Mode::Ollama => "ollama",
                Mode::Echo => "echo",
            }),
            Some(url),
            model,
            false,
        )
        .unwrap()
    }

    /// A stand-in Ollama on a random loopback port. `/api/chat` answers with
    /// `<first role>:<message count>` split across two NDJSON lines.
    async fn fake_ollama(models: &'static [&'static str]) -> String {
        fake_ollama_with(models, true).await
    }

    async fn fake_ollama_with(models: &'static [&'static str], chat_ok: bool) -> String {
        let app = Router::new()
            .route(
                "/api/tags",
                get(move || async move {
                    axum::Json(json!({"models": models.iter().map(|m| json!({"name": m})).collect::<Vec<_>>()}))
                }),
            )
            .route(
                "/api/chat",
                post(move |JsonBody(body): JsonBody<Value>| async move {
                    if !chat_ok {
                        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
                    }
                    let messages = body["messages"].as_array().unwrap();
                    assert_eq!(body["stream"], true);
                    let first = messages[0]["role"].as_str().unwrap();
                    let lines = format!(
                        "{}\n{}\n{}\n",
                        json!({"message":{"role":"assistant","content":format!("{first}:")},"done":false}),
                        json!({"message":{"role":"assistant","content":messages.len().to_string()},"done":false}),
                        json!({"message":{"role":"assistant","content":""},"done":true}),
                    );
                    ([(header::CONTENT_TYPE, "application/x-ndjson")], lines).into_response()
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        format!("http://{addr}")
    }

    async fn collect(cfg: &ModelConfig, history: &[ChatTurn]) -> (Generation, Vec<String>) {
        let (tx, mut rx) = mpsc::channel(64);
        let generation = generate(cfg, history, tx).await;
        let mut deltas = Vec::new();
        while let Ok(delta) = rx.try_recv() {
            deltas.push(delta);
        }
        (generation, deltas)
    }

    #[test]
    fn config_parses_and_guards_the_url() {
        let default = ModelConfig::from_values(None, None, None, false).unwrap();
        assert_eq!(default.mode, Mode::Auto);
        assert_eq!(default.ollama_model, None);
        assert!(
            ModelConfig::from_values(Some("echo"), None, Some(" m "), false)
                .is_ok_and(|c| c.mode == Mode::Echo && c.ollama_model.as_deref() == Some("m"))
        );
        assert!(ModelConfig::from_values(Some("gpt"), None, None, false).is_err());
        for ok in [
            "http://localhost:11434",
            "http://[::1]:11434",
            "http://127.0.0.2:1",
        ] {
            assert!(validated_url(ok, false).is_ok(), "{ok}");
        }
        for bad in [
            "http://192.168.1.5:11434",
            "https://api.example.com",
            "ftp://127.0.0.1",
        ] {
            assert!(validated_url(bad, false).is_err(), "{bad}");
        }
        assert!(validated_url("http://192.168.1.5:11434", true).is_ok());
    }

    #[test]
    fn history_is_capped_keeping_newest() {
        let mut history = Vec::new();
        for i in 0..MAX_HISTORY_TURNS + 5 {
            push_turn(&mut history, ChatTurn::user(i.to_string()));
        }
        assert_eq!(history.len(), MAX_HISTORY_TURNS);
        assert_eq!(history[0].content, "5");
        assert_eq!(
            history.last().unwrap().content,
            (MAX_HISTORY_TURNS + 4).to_string()
        );
    }

    #[test]
    fn chat_lines_parse() {
        assert_eq!(
            parse_chat_line(r#"{"message":{"content":"hi"},"done":false}"#),
            Ok(("hi".into(), false))
        );
        assert_eq!(
            parse_chat_line(r#"{"done":true}"#),
            Ok((String::new(), true))
        );
        assert_eq!(parse_chat_line(r#"{"error":"boom"}"#), Err("boom".into()));
        assert!(parse_chat_line("not json").is_err());
    }

    #[tokio::test]
    async fn streams_a_reply_from_ollama_with_system_prompt_and_history() {
        let url = fake_ollama(&["llama3.2:latest", "other:1b"]).await;
        let history = [
            ChatTurn::user("hi"),
            ChatTurn::assistant("hello"),
            ChatTurn::user("again"),
        ];
        let (generation, deltas) = collect(&cfg(Mode::Ollama, &url, None), &history).await;
        assert!(generation.error.is_none(), "{:?}", generation.error);
        assert_eq!(generation.text, "system:4");
        assert_eq!(deltas, ["system:", "4"]);
    }

    #[tokio::test]
    async fn resolves_configured_or_first_model() {
        let url = fake_ollama(&["a:1", "b:2"]).await;
        assert_eq!(
            resolve_model(&cfg(Mode::Auto, &url, None)).await.unwrap(),
            "a:1"
        );
        assert_eq!(
            resolve_model(&cfg(Mode::Auto, &url, Some("b:2")))
                .await
                .unwrap(),
            "b:2"
        );
        let missing = resolve_model(&cfg(Mode::Auto, &url, Some("zzz")))
            .await
            .unwrap_err();
        assert!(missing.contains("ollama pull zzz"), "{missing}");
        let empty = fake_ollama(&[]).await;
        assert!(resolve_model(&cfg(Mode::Auto, &empty, None)).await.is_err());
    }

    #[tokio::test]
    async fn auto_falls_back_to_echo_when_ollama_is_down() {
        // Nothing listens on port 1.
        let (generation, deltas) = collect(
            &cfg(Mode::Auto, "http://127.0.0.1:1", None),
            &[ChatTurn::user("ping")],
        )
        .await;
        assert!(generation.error.is_none());
        assert_eq!(
            generation.text,
            "Local brain link is working. You said: ping"
        );
        assert!(!deltas.is_empty());
    }

    #[tokio::test]
    async fn ollama_mode_reports_an_error_instead_of_echoing() {
        let (generation, deltas) = collect(
            &cfg(Mode::Ollama, "http://127.0.0.1:1", None),
            &[ChatTurn::user("ping")],
        )
        .await;
        assert_eq!(
            generation.error.as_ref().map(|e| e.0),
            Some("model_unavailable")
        );
        assert!(generation.text.is_empty() && deltas.is_empty());
    }

    #[tokio::test]
    async fn chat_http_error_before_output_falls_back_in_auto_mode() {
        let url = fake_ollama_with(&["m:1"], false).await;
        let history = [ChatTurn::user("x")];
        let (auto, _) = collect(&cfg(Mode::Auto, &url, None), &history).await;
        assert!(auto.error.is_none());
        assert_eq!(auto.text, "Local brain link is working. You said: x");
        let (strict, deltas) = collect(&cfg(Mode::Ollama, &url, None), &history).await;
        assert_eq!(strict.error.as_ref().map(|e| e.0), Some("model_error"));
        assert!(strict.text.is_empty() && deltas.is_empty());
    }

    #[tokio::test]
    async fn diagnostics_reflect_adapter_state() {
        let url = fake_ollama(&["a:1"]).await;
        assert_eq!(diagnostics(&cfg(Mode::Auto, &url, None)).await.0, "ok");
        assert_eq!(
            diagnostics(&cfg(Mode::Auto, "http://127.0.0.1:1", None))
                .await
                .0,
            "degraded"
        );
        assert_eq!(
            diagnostics(&cfg(Mode::Ollama, "http://127.0.0.1:1", None))
                .await
                .0,
            "error"
        );
        assert_eq!(
            diagnostics(&cfg(Mode::Echo, &url, None)).await.0,
            "degraded"
        );
    }
}
