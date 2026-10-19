//! Pinned local model contract shared by the Windows chat adapter and the
//! Neura Engine sidecar.
//!
//! Neura never installs, downloads, starts or stops a model. The operator owns
//! the separately installed Ollama daemon and the pinned model; Neura only
//! verifies the daemon's reported manifest identity before any
//! request text is submitted, and fails closed otherwise. There is no cloud or
//! alternative-model fallback. The operator's daemon is a trusted dependency:
//! tag resolution in show and chat is not atomic, nor is this weight attestation.
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
/// SHA-256 of the published Ollama manifest, reviewed 2026-10-19. A tag alone
/// and family/size/quantization metadata do not identify the selected weights.
pub const MANIFEST_DIGEST: &str =
    "sha256:0edcdef34593eac1aa2be9c7d06c432dcf81945adca5eca2f27662c18f168ba0";
/// Conservative source-checked floor for the explicit :local routing contract.
/// Only stable numeric releases are admitted; unknown/dev versions fail closed.
pub const MIN_OLLAMA_VERSION: &str = "0.18.0";
const MAX_SHOW_RESPONSE: usize = 131_072;
const MAX_TAGS_RESPONSE: usize = 1_048_576;
const MAX_VERSION_RESPONSE: usize = 1_024;

/// Content-free reason a pinned local model cannot be used right now.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModelUnavailable {
    /// The loopback daemon did not answer (not running, wrong port, timeout).
    Unreachable,
    /// The daemon does not advertise a supported stable Ollama version.
    UnsupportedVersion,
    /// The daemon answered but does not have the pinned tag installed.
    NotInstalled,
    /// The tag resolves to a remote/cloud model.
    Remote,
    /// The reported manifest, family, size or quantization differs from the pin.
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
            Self::UnsupportedVersion => "unsupported_version",
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
/// Only Windows is admitted; physical-device acceptance remains outstanding.
#[cfg(not(windows))]
pub fn memory_admitted() -> bool {
    false
}

/// HTTP client bound to one numeric loopback Ollama endpoint: no proxy, no
/// redirects, short connect deadline. The only way to reach the daemon through
/// this module, so callers cannot point verification or chat elsewhere.
pub struct LoopbackClient {
    inner: reqwest::Client,
    endpoint: String,
}

impl LoopbackClient {
    /// Accepts only `http://127.0.0.1:<port>` or `http://[::1]:<port>` with no
    /// path, query, fragment or credentials. No DNS names, LAN or public hosts.
    #[allow(clippy::result_unit_err)]
    pub fn new(endpoint: &str, timeout: Duration) -> Result<Self, ()> {
        let url = reqwest::Url::parse(endpoint).map_err(|_| ())?;
        // Numeric literals only: a DNS name is never resolved or trusted.
        let loopback = url
            .host_str()
            .map(|host| host.trim_start_matches('[').trim_end_matches(']'))
            .and_then(|host| host.parse::<std::net::IpAddr>().ok())
            .is_some_and(|ip| ip.is_loopback());
        if url.scheme() != "http"
            || !loopback
            || url.port().is_none()
            || url.path() != "/"
            || url.query().is_some()
            || url.fragment().is_some()
            || !url.username().is_empty()
            || url.password().is_some()
        {
            return Err(());
        }
        let inner = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(2))
            .timeout(timeout)
            .build()
            .map_err(|_| ())?;
        Ok(Self {
            inner,
            endpoint: endpoint.trim_end_matches('/').to_owned(),
        })
    }

    /// GET a fixed daemon API path such as `/api/tags`.
    pub fn get(&self, path: &'static str) -> reqwest::RequestBuilder {
        self.inner.get(format!("{}{path}", self.endpoint))
    }

    /// POST a JSON body to a fixed daemon API path such as `/api/chat`.
    pub fn post_json(&self, path: &'static str, body: &Value) -> reqwest::RequestBuilder {
        self.inner
            .post(format!("{}{path}", self.endpoint))
            .json(body)
    }
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

fn supported_version(version: &str) -> bool {
    let parts: Vec<_> = version.split('.').collect();
    if parts.len() != 3
        || parts
            .iter()
            .any(|part| part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()))
    {
        return false;
    }
    let Ok(parts) = parts
        .iter()
        .map(|p| p.parse::<u64>())
        .collect::<Result<Vec<_>, _>>()
    else {
        return false;
    };
    parts.as_slice() >= [0, 18, 0].as_slice()
}

/// Confirm a compatible daemon reports the reviewed manifest installed locally.
/// Sends only the model name; never any conversation or fixture text.
pub async fn verify_pinned_model(client: &LoopbackClient) -> Result<(), ModelUnavailable> {
    let response = client
        .get("/api/version")
        .send()
        .await
        .map_err(|_| ModelUnavailable::Unreachable)?;
    let version = bounded_json(response, MAX_VERSION_RESPONSE)
        .await
        .map_err(|_| ModelUnavailable::UnsupportedVersion)?;
    if !version["version"].as_str().is_some_and(supported_version) {
        return Err(ModelUnavailable::UnsupportedVersion);
    }

    let response = client
        .get("/api/tags")
        .send()
        .await
        .map_err(|_| ModelUnavailable::Unreachable)?;
    let tags = bounded_json(response, MAX_TAGS_RESPONSE)
        .await
        .map_err(|_| ModelUnavailable::Malformed)?;
    let models = tags["models"]
        .as_array()
        .ok_or(ModelUnavailable::Malformed)?;
    let mut matches = models
        .iter()
        .filter(|model| model["name"] == MODEL || model["model"] == MODEL);
    let installed = matches.next().ok_or(ModelUnavailable::NotInstalled)?;
    if matches.next().is_some() {
        return Err(ModelUnavailable::Malformed);
    }
    if installed.get("remote_host").is_some() || installed.get("remote_model").is_some() {
        return Err(ModelUnavailable::Remote);
    }
    // Ollama /api/tags normally returns bare hex; registry identities use
    // sha256:<hex>. Accept only those two representations of the reviewed hash.
    if !installed["digest"].as_str().is_some_and(|digest| {
        digest == MANIFEST_DIGEST || digest == &MANIFEST_DIGEST["sha256:".len()..]
    }) {
        return Err(ModelUnavailable::Mismatch);
    }
    let response = client
        .post_json("/api/show", &json!({"model": LOCAL_MODEL}))
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
    /// Largest total response body accepted, checked before each chunk is
    /// buffered so one oversized chunk cannot force a large allocation.
    pub max_response: usize,
}

/// Why a stream ended without a verified completion.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StreamError {
    /// Transport failure or non-success status.
    Transport,
    /// Malformed line, remote model, tool call, error field or missing `done`.
    Protocol,
    /// A line, the total output or the response body exceeded its budget.
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
    client: &LoopbackClient,
    payload: &Value,
    limits: StreamLimits,
    mut on_delta: F,
) -> Result<Zeroizing<String>, StreamError>
where
    F: FnMut(&str) -> bool,
{
    let mut response = client
        .post_json("/api/chat", payload)
        .send()
        .await
        .map_err(|_| StreamError::Transport)?;
    if !response.status().is_success() {
        return Err(StreamError::Transport);
    }
    let mut pending = Zeroizing::new(Vec::new());
    let mut text = Zeroizing::new(String::new());
    let mut received = 0usize;
    loop {
        let Some(chunk) = response.chunk().await.map_err(|_| StreamError::Transport)? else {
            // The body ended without a final `done` line.
            return Err(StreamError::Protocol);
        };
        received += chunk.len();
        if received > limits.max_response {
            return Err(StreamError::Exhausted);
        }
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
    use axum::{
        body::Body,
        http::StatusCode,
        response::IntoResponse,
        routing::{get, post},
        Json, Router,
    };

    pub(crate) fn pinned_tags() -> Value {
        json!({"models":[{"name":"qwen3:4b-instruct",
            "digest":"0edcdef34593eac1aa2be9c7d06c432dcf81945adca5eca2f27662c18f168ba0"}]})
    }

    pub(crate) fn metadata_router() -> Router {
        Router::new()
            .route(
                "/api/version",
                get(|| async { Json(json!({"version":"0.18.0"})) }),
            )
            .route("/api/tags", get(|| async { Json(pinned_tags()) }))
    }

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

    fn http(endpoint: &str) -> LoopbackClient {
        LoopbackClient::new(endpoint, Duration::from_secs(5)).unwrap()
    }

    #[tokio::test]
    async fn unsupported_daemon_is_rejected_before_model_lookup() {
        use std::sync::{
            atomic::{AtomicUsize, Ordering},
            Arc,
        };
        let shows = Arc::new(AtomicUsize::new(0));
        let seen = shows.clone();
        let router = Router::new()
            .route(
                "/api/version",
                get(|| async { Json(json!({"version":"0.17.0"})) }),
            )
            .route(
                "/api/show",
                post(move || {
                    seen.fetch_add(1, Ordering::SeqCst);
                    async { Json(pinned_info()) }
                }),
            );
        let (endpoint, task) = serve(router).await;
        assert!(verify_pinned_model(&http(&endpoint)).await.is_err());
        assert_eq!(shows.load(Ordering::SeqCst), 0);
        task.abort();
    }

    #[tokio::test]
    async fn retargeted_tag_is_rejected_even_with_matching_model_metadata() {
        let mut tags = pinned_tags();
        tags["models"][0]["digest"] = json!(format!("sha256:{}", "f".repeat(64)));
        let router = Router::new()
            .route(
                "/api/version",
                get(|| async { Json(json!({"version":"0.18.0"})) }),
            )
            .route("/api/tags", get(move || async move { Json(tags) }))
            .route("/api/show", post(|| async { Json(pinned_info()) }));
        let (endpoint, task) = serve(router).await;
        assert!(verify_pinned_model(&http(&endpoint)).await.is_err());
        task.abort();
    }

    #[tokio::test]
    async fn accepts_bare_and_prefixed_published_manifest_digest() {
        for digest in [
            "0edcdef34593eac1aa2be9c7d06c432dcf81945adca5eca2f27662c18f168ba0",
            "sha256:0edcdef34593eac1aa2be9c7d06c432dcf81945adca5eca2f27662c18f168ba0",
        ] {
            let tags = json!({"models":[{"name":"qwen3:4b-instruct","digest":digest}]});
            let router = Router::new()
                .route(
                    "/api/version",
                    get(|| async { Json(json!({"version":"0.18.0"})) }),
                )
                .route("/api/tags", get(move || async move { Json(tags) }))
                .route("/api/show", post(|| async { Json(pinned_info()) }));
            let (endpoint, task) = serve(router).await;
            assert_eq!(verify_pinned_model(&http(&endpoint)).await, Ok(()));
            task.abort();
        }
    }

    #[test]
    fn pin_matches_the_reviewed_model() {
        // Independent literals: changing the pin must also change this test.
        assert_eq!(MODEL, "qwen3:4b-instruct");
        assert_eq!(LOCAL_MODEL, "qwen3:4b-instruct:local");
        assert_eq!(FAMILY, "qwen3");
        assert_eq!(PARAMETER_SIZE, "4.0B");
        assert_eq!(QUANTIZATION, "Q4_K_M");
        assert_eq!(ENDPOINT, "http://127.0.0.1:11434");
        assert_eq!(MIN_OLLAMA_VERSION, "0.18.0");
        assert_eq!(
            MANIFEST_DIGEST,
            "sha256:0edcdef34593eac1aa2be9c7d06c432dcf81945adca5eca2f27662c18f168ba0"
        );
    }

    #[test]
    fn only_supported_stable_daemon_versions_are_admitted() {
        for version in ["0.18.0", "0.18.1", "0.24.0", "0.40.6", "1.0.0"] {
            assert!(supported_version(version), "{version}");
        }
        for version in [
            "",
            "0.17.99",
            "0.18",
            "0.18.0.1",
            "0.18.0-rc1",
            "dev",
            " 0.18.0",
            "999999999999999999999.0.0",
        ] {
            assert!(!supported_version(version), "{version}");
        }
    }

    #[test]
    fn client_accepts_only_numeric_loopback_http() {
        for ok in [ENDPOINT, "http://127.0.0.1:8080/", "http://[::1]:11434"] {
            assert!(
                LoopbackClient::new(ok, Duration::from_secs(1)).is_ok(),
                "{ok}"
            );
        }
        for bad in [
            "https://127.0.0.1:11434",
            "http://localhost:11434",
            "http://192.168.1.5:11434",
            "http://0.0.0.0:11434",
            "http://ollama.com:11434",
            "http://127.0.0.1",
            "http://127.0.0.1:11434/api",
            "http://127.0.0.1:11434/?x=1",
            "http://user:pw@127.0.0.1:11434",
            "not a url",
        ] {
            assert!(
                LoopbackClient::new(bad, Duration::from_secs(1)).is_err(),
                "{bad}"
            );
        }
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
            let router = metadata_router().route(
                "/api/show",
                post(move |Json(request): Json<Value>| async move {
                    assert_eq!(request, json!({"model":"qwen3:4b-instruct:local"}));
                    Json(info)
                }),
            );
            let (endpoint, task) = serve(router).await;
            assert_eq!(verify_pinned_model(&http(&endpoint)).await, expected);
            task.abort();
        }
    }

    #[tokio::test]
    async fn missing_model_and_absent_daemon_are_distinct() {
        let router = metadata_router().route(
            "/api/show",
            post(|| async { (StatusCode::NOT_FOUND, "model not found").into_response() }),
        );
        let (endpoint, task) = serve(router).await;
        assert_eq!(
            verify_pinned_model(&http(&endpoint)).await,
            Err(ModelUnavailable::NotInstalled)
        );
        task.abort();
        // Port 1 on loopback is not an Ollama daemon.
        assert_eq!(
            verify_pinned_model(&http("http://127.0.0.1:1")).await,
            Err(ModelUnavailable::Unreachable)
        );
    }

    #[tokio::test]
    async fn oversized_metadata_is_malformed() {
        let router = metadata_router().route(
            "/api/show",
            post(|| async { Json(json!({"pad":"x".repeat(MAX_SHOW_RESPONSE)})) }),
        );
        let (endpoint, task) = serve(router).await;
        assert_eq!(
            verify_pinned_model(&http(&endpoint)).await,
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
        let result = stream_chat(&http(&endpoint), &json!({}), limits, |delta| {
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
        max_response: 4096,
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
            // One newline-free chunk over the body budget is refused before buffering.
            ("\n".repeat(5000), StreamError::Exhausted),
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
        let result = stream_chat(&http(&endpoint), &json!({}), LIMITS, |_| false).await;
        assert_eq!(result.unwrap_err(), StreamError::Stopped);
        task.abort();
    }
}
