//! Minimal non-streaming Anthropic Messages API client, used by the swarm's
//! critic and memory agents. Mirrors the JSON shape already hand-rolled in
//! the Dart app's `NeuraAiService.completeOnce`
//! (`lib/services/neura_ai_service.dart`) so both call sites hit the API the
//! same way -- this client just isn't the one driving the main chat stream.

use std::time::Duration;

use serde::Deserialize;
use serde_json::json;

const ENDPOINT: &str = "https://api.anthropic.com/v1/messages";
const MODEL: &str = "claude-sonnet-5";
const ANTHROPIC_VERSION: &str = "2023-06-01";

/// These are quick, low-effort single-purpose calls (see `complete`'s
/// `max_tokens` doc), so a generous-but-bounded timeout is enough to stop a
/// stalled connection from hanging the calling agent forever -- both
/// agents already degrade gracefully on any `ClientError`, so a timeout
/// just becomes one more input to that same fallback path.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Debug)]
pub enum ClientError {
    Http(String),
    Api(String),
}

impl std::fmt::Display for ClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ClientError::Http(e) => write!(f, "HTTP error: {e}"),
            ClientError::Api(e) => write!(f, "API error: {e}"),
        }
    }
}

impl std::error::Error for ClientError {}

#[derive(Deserialize)]
struct MessagesResponse {
    content: Vec<ContentBlock>,
}

#[derive(Deserialize)]
struct ContentBlock {
    #[serde(rename = "type")]
    block_type: String,
    text: Option<String>,
}

/// Runs a single non-streaming completion. `max_tokens` is deliberately
/// small -- these are quick, single-purpose reviewer/extractor calls, not a
/// conversational reply.
pub async fn complete(
    base_url: &str,
    api_key: &str,
    system_prompt: &str,
    user_message: &str,
    max_tokens: u32,
) -> Result<String, ClientError> {
    let client = reqwest::Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .build()
        .map_err(|e| ClientError::Http(e.to_string()))?;

    let body = json!({
        "model": MODEL,
        "max_tokens": max_tokens,
        "stream": false,
        "thinking": {"type": "disabled"},
        "output_config": {"effort": "low"},
        "system": [
            {"type": "text", "text": system_prompt}
        ],
        "messages": [
            {"role": "user", "content": user_message}
        ],
    });

    let response = client
        .post(base_url)
        .header("content-type", "application/json")
        .header("x-api-key", api_key)
        .header("anthropic-version", ANTHROPIC_VERSION)
        .json(&body)
        .send()
        .await
        .map_err(|e| ClientError::Http(e.to_string()))?;

    let status = response.status();
    let text = response
        .text()
        .await
        .map_err(|e| ClientError::Http(e.to_string()))?;

    if !status.is_success() {
        return Err(ClientError::Api(format!("{status}: {text}")));
    }

    let parsed: MessagesResponse =
        serde_json::from_str(&text).map_err(|e| ClientError::Api(e.to_string()))?;

    let reply = parsed
        .content
        .into_iter()
        .filter(|b| b.block_type == "text")
        .filter_map(|b| b.text)
        .collect::<Vec<_>>()
        .join("");

    Ok(reply)
}

/// The real Anthropic endpoint. Tests point `complete` at a mock server URL
/// instead, so it's kept as a plain constant rather than baked into the
/// function signature's default.
pub fn default_endpoint() -> &'static str {
    ENDPOINT
}
