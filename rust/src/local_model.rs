//! Pinned local model contract shared by the Windows chat adapter and the
//! Neura Engine sidecar.
//!
//! Neura never installs, downloads, starts or stops a model. The operator owns
//! the separately installed Ollama daemon and the pinned model; Neura only
//! verifies that the loopback daemon serves exactly that local model before any
//! request text is submitted, and fails closed otherwise. There is no cloud or
//! alternative-model fallback.
use serde_json::{json, Value};
use std::time::Duration;
use zeroize::Zeroizing;

/// Ollama tag that must resolve to the pinned weights.
pub const MODEL: &str = "qwen3:4b-instruct";
/// Current Ollama's explicit source suffix rejects remote aliases at request
/// execution time, including a tag replacement after metadata preflight.
pub const LOCAL_MODEL: &str = "qwen3:4b-instruct:local";
/// Fixed numeric loopback endpoint. Never configurable from IPC or a URL.
pub const ENDPOINT: &str = "http://127.0.0.1:11434";
pub const FAMILY: &str = "qwen3";
pub const PARAMETER_SIZE: &str = "4.0B";
pub const QUANTIZATION: &str = "Q4_K_M";
const MAX_SHOW_RESPONSE: usize = 131_072;

/// Content-free reason a pinned local model cannot be used right now.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModelUnavailable {
    /// The loopback daemon did not answer (not running, wrong port, timeout).
    Unreachable,
    /// The daemon answered but does not have the pinned tag installed.
    NotInstalled,
    /// The tag resolves to a remote/cloud model.
    Remote,
    /// The tag resolves to a different family, size or quantization.
    Mismatch,
    /// The daemon's metadata was malformed or exceeded its size budget.
    Malformed,
    /// The host does not meet the admission memory budget.
    InsufficientMemory,
}

impl ModelUnavailable {
    /// Stable machine-readable code. Never includes daemon output.
    pub fn code(self) -> &'static str {
        match self {
            Self::Unreachable => "unreachable",
            Self::NotInstalled => "not_installed",
            Self::Remote => "remote_model",
            Self::Mismatch => "model_mismatch",
            Self::Malformed => "malformed_metadata",
            Self::InsufficientMemory => "insufficient_memory",
        }
    }
}

/// Windows admission budget: at least 7 GiB installed and 3.5 GiB available.
#[cfg(windows)]
pub fn memory_admitted() -> bool {
    use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};
    // SAFETY: MEMORYSTATUSEX is a plain output structure initialized with its size.
    let mut memory: MEMORYSTATUSEX = unsafe { std::mem::zeroed() };
    memory.dwLength = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
    (unsafe { GlobalMemoryStatusEx(&mut memory) != 0 })
        && memory.ullTotalPhys >= 7 * 1024 * 1024 * 1024
        && memory.ullAvailPhys >= 3584 * 1024 * 1024
}
/// Only the measured Windows target is admitted.
#[cfg(not(windows))]
pub fn memory_admitted() -> bool {
    false
}

/// Loopback-only HTTP client: no proxy, no redirects, short connect deadline.
#[allow(clippy::result_unit_err)]
pub fn client(timeout: Duration) -> Result<reqwest::Client, ()> {
    reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(2))
        .timeout(timeout)
        .build()
        .map_err(|_| ())
}

/// Read a whole JSON body within `limit` bytes; the buffer is zeroized.
#[allow(clippy::result_unit_err)]
pub async fn bounded_json(mut response: reqwest::Response, limit: usize) -> Result<Value, ()> {
    if !response.status().is_success() {
        return Err(());
    }
    let mut bytes = Zeroizing::new(Vec::new());
    while let Some(chunk) = response.chunk().await.map_err(|_| ())? {
        if bytes.len() + chunk.len() > limit {
            return Err(());
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&bytes).map_err(|_| ())
}

/// Confirm the pinned tag is installed locally with the pinned weights.
/// Sends only the model name; never any conversation or fixture text.
pub async fn verify_pinned_model(
    client: &reqwest::Client,
    endpoint: &str,
) -> Result<(), ModelUnavailable> {
    let response = client
        .post(format!("{endpoint}/api/show"))
        .json(&json!({"model": MODEL}))
        .send()
        .await
        .map_err(|_| ModelUnavailable::Unreachable)?;
    let status = response.status();
    if status == reqwest::StatusCode::NOT_FOUND {
        return Err(ModelUnavailable::NotInstalled);
    }
    if !status.is_success() {
        return Err(ModelUnavailable::Malformed);
    }
    let info = bounded_json(response, MAX_SHOW_RESPONSE)
        .await
        .map_err(|_| ModelUnavailable::Malformed)?;
    if info.get("remote_host").is_some() || info.get("remote_model").is_some() {
        return Err(ModelUnavailable::Remote);
    }
    let details = &info["details"];
    if details["family"] != FAMILY
        || details["parameter_size"] != PARAMETER_SIZE
        || details["quantization_level"] != QUANTIZATION
    {
        return Err(ModelUnavailable::Mismatch);
    }
    Ok(())
}

/// Budgets for one streamed `/api/chat` response.
#[derive(Clone, Copy, Debug)]
pub struct StreamLimits {
    /// Largest single NDJSON line accepted from the daemon.
    pub max_line: usize,
    /// Largest total assistant text accepted.
    pub max_output: usize,
}

/// Why a stream ended without a verified completion.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StreamError {
    /// Transport failure or non-success status.
    Transport,
    /// Malformed line, remote model, tool call, error field or missing `done`.
    Protocol,
    /// A line or the total output exceeded its budget.
    Exhausted,
    /// The delta consumer asked to stop.
    Stopped,
}

/// Inspect one streamed line, returning its text delta and whether it is final.
fn stream_line(line: &[u8]) -> Result<(String, bool), StreamError> {
    let value: Value = serde_json::from_slice(line).map_err(|_| StreamError::Protocol)?;
    let message = &value["message"];
    if value.get("error").is_some()
        || value.get("remote_host").is_some()
        || value.get("remote_model").is_some()
        || message["role"] != "assistant"
        || message
            .get("tool_calls")
            .is_some_and(|v| !v.as_array().is_some_and(|a| a.is_empty()))
    {
        return Err(StreamError::Protocol);
    }
    let delta = message["content"]
        .as_str()
        .ok_or(StreamError::Protocol)?
        .to_owned();
    Ok((delta, value["done"] == true))
}

/// Submit a streaming chat request and hand each text delta to `on_delta`.
///
/// Returns the complete assistant text only after the daemon's final `done`
/// line. Every budget failure is terminal; nothing is retried. Dropping the
/// returned future drops the HTTP response, which closes the connection and
/// lets the daemon abandon generation.
pub async fn stream_chat<F>(
    client: &reqwest::Client,
    endpoint: &str,
    payload: &Value,
    limits: StreamLimits,
    mut on_delta: F,
) -> Result<Zeroizing<String>, StreamError>
where
    F: FnMut(&str) -> bool,
{
    let mut response = client
        .post(format!("{endpoint}/api/chat"))
        .json(payload)
        .send()
        .await
        .map_err(|_| StreamError::Transport)?;
    if !response.status().is_success() {
        return Err(StreamError::Transport);
    }
    let mut pending = Zeroizing::new(Vec::new());
    let mut text = Zeroizing::new(String::new());
    loop {
        let Some(chunk) = response.chunk().await.map_err(|_| StreamError::Transport)? else {
            // The body ended without a final `done` line.
            return Err(StreamError::Protocol);
        };
        pending.extend_from_slice(&chunk);
        while let Some(end) = pending.iter().position(|byte| *byte == b'\n') {
            if end > limits.max_line {
                return Err(StreamError::Exhausted);
            }
            let line: Zeroizing<Vec<u8>> = Zeroizing::new(pending.drain(..=end).collect());
            let line = &line[..end];
            if line.iter().all(u8::is_ascii_whitespace) {
                continue;
            }
            let (delta, done) = stream_line(line)?;
            if text.len() + delta.len() > limits.max_output {
                return Err(StreamError::Exhausted);
            }
            if !delta.is_empty() {
                text.push_str(&delta);
                if !on_delta(&delta) {
                    return Err(StreamError::Stopped);
                }
            }
            if done {
                if text.trim().is_empty() {
                    return Err(StreamError::Protocol);
                }
                return Ok(text);
            }
        }
        if pending.len() > limits.max_line {
            return Err(StreamError::Exhausted);
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use axum::{body::Body, http::StatusCode, response::IntoResponse, routing::post, Json, Router};

    pub(crate) fn pinned_info() -> Value {
        json!({"details":{"family":FAMILY,"parameter_size":PARAMETER_SIZE,"quantization_level":QUANTIZATION}})
    }

    async fn serve(router: Router) -> (String, tokio::task::JoinHandle<()>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        (endpoint, task)
    }

    fn http() -> reqwest::Client {
        client(Duration::from_secs(5)).unwrap()
    }

    #[tokio::test]
    async fn verifies_only_the_pinned_local_model() {
        let cases = [
            (pinned_info(), Ok(())),
            (
                {
                    let mut info = pinned_info();
                    info["remote_host"] = json!("https://ollama.com");
                    info
                },
                Err(ModelUnavailable::Remote),
            ),
            (
                {
                    let mut info = pinned_info();
                    info["details"]["quantization_level"] = json!("Q8_0");
                    info
                },
                Err(ModelUnavailable::Mismatch),
            ),
            (json!({}), Err(ModelUnavailable::Mismatch)),
        ];
        for (info, expected) in cases {
            let router = Router::new().route("/api/show", post(move || async move { Json(info) }));
            let (endpoint, task) = serve(router).await;
            assert_eq!(verify_pinned_model(&http(), &endpoint).await, expected);
            task.abort();
        }
    }

    #[tokio::test]
    async fn missing_model_and_absent_daemon_are_distinct() {
        let router = Router::new().route(
            "/api/show",
            post(|| async { (StatusCode::NOT_FOUND, "model not found").into_response() }),
        );
        let (endpoint, task) = serve(router).await;
        assert_eq!(
            verify_pinned_model(&http(), &endpoint).await,
            Err(ModelUnavailable::NotInstalled)
        );
        task.abort();
        // Port 1 on loopback is not an Ollama daemon.
        assert_eq!(
            verify_pinned_model(&http(), "http://127.0.0.1:1").await,
            Err(ModelUnavailable::Unreachable)
        );
    }

    #[tokio::test]
    async fn oversized_metadata_is_malformed() {
        let router = Router::new().route(
            "/api/show",
            post(|| async { Json(json!({"pad":"x".repeat(MAX_SHOW_RESPONSE)})) }),
        );
        let (endpoint, task) = serve(router).await;
        assert_eq!(
            verify_pinned_model(&http(), &endpoint).await,
            Err(ModelUnavailable::Malformed)
        );
        task.abort();
    }

    fn line(content: &str, done: bool) -> String {
        format!(
            "{}\n",
            json!({"message":{"role":"assistant","content":content},"done":done})
        )
    }

    async fn stream_with(body: String, limits: StreamLimits) -> Result<String, StreamError> {
        let router =
            Router::new().route("/api/chat", post(move || async move { Body::from(body) }));
        let (endpoint, task) = serve(router).await;
        let mut deltas = Vec::new();
        let result = stream_chat(&http(), &endpoint, &json!({}), limits, |delta| {
            deltas.push(delta.to_owned());
            true
        })
        .await
        .map(|text| text.to_string());
        task.abort();
        if let Ok(text) = &result {
            assert_eq!(&deltas.concat(), text);
        }
        result
    }

    const LIMITS: StreamLimits = StreamLimits {
        max_line: 1024,
        max_output: 64,
    };

    #[tokio::test]
    async fn streams_deltas_until_the_final_done_line() {
        let body = [
            line("Local ", false),
            line("link works.", false),
            line("", true),
        ]
        .concat();
        assert_eq!(
            stream_with(body, LIMITS).await.unwrap(),
            "Local link works."
        );
    }

    #[tokio::test]
    async fn rejects_incomplete_remote_tool_error_and_oversized_streams() {
        let remote = format!(
            "{}\n",
            json!({"message":{"role":"assistant","content":"x"},"done":true,"remote_host":"https://ollama.com"})
        );
        let tool = format!(
            "{}\n",
            json!({"message":{"role":"assistant","content":"x","tool_calls":[{}]},"done":true})
        );
        let error = format!("{}\n", json!({"error":"boom"}));
        for (body, expected) in [
            (line("partial", false), StreamError::Protocol),
            (remote, StreamError::Protocol),
            (tool, StreamError::Protocol),
            (error, StreamError::Protocol),
            ("not json\n".to_string(), StreamError::Protocol),
            (line("", true), StreamError::Protocol),
            (line(&"x".repeat(65), true), StreamError::Exhausted),
            (line(&"x".repeat(2048), true), StreamError::Exhausted),
            ("x".repeat(2048), StreamError::Exhausted),
        ] {
            assert_eq!(stream_with(body, LIMITS).await.unwrap_err(), expected);
        }
    }

    #[tokio::test]
    async fn consumer_can_stop_the_stream() {
        let body = [line("one ", false), line("two", true)].concat();
        let router =
            Router::new().route("/api/chat", post(move || async move { Body::from(body) }));
        let (endpoint, task) = serve(router).await;
        let result = stream_chat(&http(), &endpoint, &json!({}), LIMITS, |_| false).await;
        assert_eq!(result.unwrap_err(), StreamError::Stopped);
        task.abort();
    }
}
