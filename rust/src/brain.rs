//! `LlmBrain` — Neura's connection to an OpenAI-compatible chat endpoint
//! (LM Studio by default).
//!
//! The HTTP call is abstracted behind the `Transport` trait so the brain is
//! testable offline and you can swap clients. A ready `reqwest` transport ships
//! behind the `reqwest-transport` feature (see `reqwest_transport.rs`). The
//! request-building and response-parsing are pure functions with unit tests, so
//! the wire format is verified without a live server.

use serde::{Deserialize, Serialize};

/// A chat message. Serializes to `{"role": "...", "content": "..."}` — the
/// OpenAI/LM Studio shape.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMsg {
    pub role: Role,
    pub content: String,
}

impl ChatMsg {
    pub fn system(content: impl Into<String>) -> Self {
        Self { role: Role::System, content: content.into() }
    }
    pub fn user(content: impl Into<String>) -> Self {
        Self { role: Role::User, content: content.into() }
    }
    pub fn assistant(content: impl Into<String>) -> Self {
        Self { role: Role::Assistant, content: content.into() }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    System,
    User,
    Assistant,
}

/// Sampling knobs for one completion.
#[derive(Debug, Clone)]
pub struct CompletionOpts {
    pub temperature: f32,
    pub max_tokens: u32,
}

impl Default for CompletionOpts {
    fn default() -> Self {
        Self { temperature: 0.7, max_tokens: 512 }
    }
}

impl CompletionOpts {
    /// Tuned for the interpreter pass: deterministic and short.
    pub fn interpreter() -> Self {
        Self { temperature: 0.0, max_tokens: 256 }
    }
}

#[derive(Debug)]
pub enum BrainError {
    /// The transport (network layer) failed.
    Transport(String),
    /// Request could not be built or the response could not be decoded.
    Decode(String),
    /// The model returned no choices.
    EmptyResponse,
}

impl std::fmt::Display for BrainError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BrainError::Transport(e) => write!(f, "transport error: {e}"),
            BrainError::Decode(e) => write!(f, "decode error: {e}"),
            BrainError::EmptyResponse => write!(f, "model returned no choices"),
        }
    }
}
impl std::error::Error for BrainError {}

/// The HTTP seam. Implement this for whatever client you like; a `reqwest`
/// implementation is provided under the `reqwest-transport` feature.
pub trait Transport {
    /// POST a JSON `body` to `url`, return the response body as a string.
    fn post_json(&self, url: &str, body: &str) -> Result<String, BrainError>;
}

/// Neura's brain: config + a transport. Cheap to construct; clone freely if
/// your transport is `Clone`.
pub struct LlmBrain<T: Transport> {
    transport: T,
    base_url: String,
    model: String,
}

impl<T: Transport> LlmBrain<T> {
    /// `base_url` is the OpenAI-compatible root, e.g. `http://localhost:1234/v1`.
    pub fn new(transport: T, base_url: impl Into<String>, model: impl Into<String>) -> Self {
        Self { transport, base_url: base_url.into(), model: model.into() }
    }

    pub fn model(&self) -> &str {
        &self.model
    }

    /// One non-streaming completion. This is what the interpreter pass uses.
    ///
    /// (Streaming SSE with barge-in cancellation is a planned extension on the
    /// transport side; it is not needed for the interpreter, which wants a
    /// single short JSON object back.)
    pub fn complete_once(
        &self,
        messages: &[ChatMsg],
        opts: CompletionOpts,
    ) -> Result<String, BrainError> {
        let body = build_request_body(&self.model, messages, &opts)?;
        let url = format!("{}/chat/completions", self.base_url.trim_end_matches('/'));
        let raw = self.transport.post_json(&url, &body)?;
        parse_completion(&raw)
    }
}

/// Build the `/chat/completions` request body. Pure + tested.
pub fn build_request_body(
    model: &str,
    messages: &[ChatMsg],
    opts: &CompletionOpts,
) -> Result<String, BrainError> {
    #[derive(Serialize)]
    struct Req<'a> {
        model: &'a str,
        messages: &'a [ChatMsg],
        temperature: f32,
        max_tokens: u32,
        stream: bool,
    }
    serde_json::to_string(&Req {
        model,
        messages,
        temperature: opts.temperature,
        max_tokens: opts.max_tokens,
        stream: false,
    })
    .map_err(|e| BrainError::Decode(e.to_string()))
}

/// Pull the assistant text out of an OpenAI-compatible response. Pure + tested.
pub fn parse_completion(raw: &str) -> Result<String, BrainError> {
    #[derive(Deserialize)]
    struct Resp {
        choices: Vec<Choice>,
    }
    #[derive(Deserialize)]
    struct Choice {
        message: Msg,
    }
    #[derive(Deserialize)]
    struct Msg {
        content: String,
    }
    let resp: Resp = serde_json::from_str(raw).map_err(|e| BrainError::Decode(e.to_string()))?;
    resp.choices
        .into_iter()
        .next()
        .map(|c| c.message.content)
        .ok_or(BrainError::EmptyResponse)
}

#[cfg(test)]
pub(crate) mod test_support {
    use super::*;

    /// A transport that returns a canned body, for offline tests.
    pub struct FakeTransport {
        pub reply: String,
        pub last_body: std::cell::RefCell<String>,
    }
    impl FakeTransport {
        pub fn new(reply: impl Into<String>) -> Self {
            Self { reply: reply.into(), last_body: std::cell::RefCell::new(String::new()) }
        }
    }
    impl Transport for FakeTransport {
        fn post_json(&self, _url: &str, body: &str) -> Result<String, BrainError> {
            *self.last_body.borrow_mut() = body.to_string();
            Ok(self.reply.clone())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::test_support::FakeTransport;
    use super::*;

    #[test]
    fn request_body_carries_model_and_messages() {
        let msgs = [ChatMsg::system("you are neura"), ChatMsg::user("hi")];
        let body = build_request_body("qwen2.5", &msgs, &CompletionOpts::interpreter()).unwrap();
        assert!(body.contains("\"model\":\"qwen2.5\""));
        assert!(body.contains("\"role\":\"system\""));
        assert!(body.contains("\"temperature\":0.0"));
        assert!(body.contains("\"stream\":false"));
    }

    #[test]
    fn parses_openai_shaped_response() {
        let raw = r#"{"choices":[{"message":{"role":"assistant","content":"hello there"}}]}"#;
        assert_eq!(parse_completion(raw).unwrap(), "hello there");
    }

    #[test]
    fn empty_choices_is_an_error() {
        let raw = r#"{"choices":[]}"#;
        assert!(matches!(parse_completion(raw), Err(BrainError::EmptyResponse)));
    }

    #[test]
    fn complete_once_round_trips_through_transport() {
        let reply = r#"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#;
        let brain = LlmBrain::new(FakeTransport::new(reply), "http://localhost:1234/v1", "local");
        let out = brain
            .complete_once(&[ChatMsg::user("ping")], CompletionOpts::default())
            .unwrap();
        assert_eq!(out, "ok");
    }
}
