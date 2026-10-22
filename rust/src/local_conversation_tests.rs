use super::*;
use axum::{
    extract::{OriginalUri, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
use tokio::{net::TcpListener, sync::Notify, task::JoinHandle};

const TOKEN: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

#[derive(Clone, Copy)]
enum Behavior {
    Normal,
    Slow,
    Oversized,
    Tools,
    TooManyTokens,
    TrimHistory,
    Redirect,
}
struct Fixture {
    behavior: Behavior,
    calls: AtomicUsize,
    completions: AtomicUsize,
    started: Notify,
    continue_reply: Notify,
}
struct Server {
    port: u16,
    fixture: Arc<Fixture>,
    task: JoinHandle<()>,
}
impl Drop for Server {
    fn drop(&mut self) {
        self.task.abort();
    }
}
impl Server {
    fn client(&self, grant: LocalTextGrant) -> LocalConversation {
        LocalConversation::new(self.port, Zeroizing::new(TOKEN.into()), grant).unwrap()
    }
}

async fn serve(behavior: Behavior) -> Server {
    let fixture = Arc::new(Fixture {
        behavior,
        calls: AtomicUsize::new(0),
        completions: AtomicUsize::new(0),
        started: Notify::new(),
        continue_reply: Notify::new(),
    });
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let app = Router::new()
        .route("/apply-template", post(handle))
        .route("/tokenize", post(handle))
        .route("/v1/chat/completions", post(handle))
        .with_state(fixture.clone());
    let task = tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    Server {
        port,
        fixture,
        task,
    }
}

async fn handle(
    State(f): State<Arc<Fixture>>,
    uri: OriginalUri,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> Response {
    f.calls.fetch_add(1, Ordering::SeqCst);
    if headers.get("authorization").and_then(|h| h.to_str().ok())
        != Some(&format!("Bearer {TOKEN}"))
    {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    if matches!(f.behavior, Behavior::Redirect) {
        // If followed, this would recursively deliver the same credential/body.
        return (
            StatusCode::TEMPORARY_REDIRECT,
            [("location", "/v1/chat/completions")],
        )
            .into_response();
    }
    match uri.path() {
        "/apply-template" => Json(json!({"prompt": body["messages"].to_string()})).into_response(),
        "/tokenize" => {
            let prompt = body["content"].as_str().unwrap();
            let users = prompt.matches("\"role\":\"user\"").count();
            let count = match f.behavior {
                Behavior::TooManyTokens => CONTEXT_TOKENS,
                Behavior::TrimHistory if users > 1 => CONTEXT_TOKENS,
                _ => 300,
            };
            Json(json!({"tokens": vec![1; count]})).into_response()
        }
        "/v1/chat/completions" => {
            f.completions.fetch_add(1, Ordering::SeqCst);
            f.started.notify_one();
            if matches!(f.behavior, Behavior::Slow) {
                f.continue_reply.notified().await;
            }
            if matches!(f.behavior, Behavior::Oversized) {
                return (
                    [("content-type", "application/json")],
                    "x".repeat(MAX_RESPONSE_BYTES + 1),
                )
                    .into_response();
            }
            if matches!(f.behavior, Behavior::Tools) {
                return Json(json!({"choices": [{"finish_reason": "tool_calls", "message": {
                    "role": "assistant", "content": "run this", "tool_calls": [{"name": "exec_shell_command"}],
                }}]})).into_response();
            }
            assert_eq!(body["max_tokens"], REPLY_TOKENS);
            assert_eq!(body["stream"], false);
            assert_eq!(body["cache_prompt"], false);
            assert_eq!(body["chat_template_kwargs"]["enable_thinking"], false);
            Json(json!({"choices": [{"finish_reason": "stop", "message": {
                "role": "assistant", "content": "Hello. What would you like to talk about?",
            }}]}))
            .into_response()
        }
        _ => StatusCode::NOT_FOUND.into_response(),
    }
}

#[tokio::test]
async fn text_turn_uses_authenticated_local_server_and_only_session_context() {
    let server = serve(Behavior::Normal).await;
    let mut client = server.client(LocalTextGrant::approve_session_text());
    assert_eq!(
        client.reply("Hello").await.unwrap().as_str(),
        "Hello. What would you like to talk about?"
    );
    assert_eq!(client.turns.len(), 1);
    assert_eq!(server.fixture.calls.load(Ordering::SeqCst), 3);
    client.stop();
    assert!(client.turns.is_empty());
    assert!(client.token.is_empty());
    assert!(matches!(
        client.reply("again").await,
        Err(LocalConversationError::Revoked)
    ));
    assert_eq!(server.fixture.calls.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn revoked_and_overlong_inputs_make_no_http_request() {
    let server = serve(Behavior::Normal).await;
    let grant = LocalTextGrant::approve_session_text();
    let mut client = server.client(grant.clone());
    assert!(matches!(
        client.reply(&"x".repeat(MAX_INPUT_BYTES + 1)).await,
        Err(LocalConversationError::InputLimit)
    ));
    grant.revoke();
    assert!(matches!(
        client.reply("private text").await,
        Err(LocalConversationError::Revoked)
    ));
    assert_eq!(server.fixture.calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn revocation_discards_inflight_output_and_prevents_later_requests() {
    let server = serve(Behavior::Slow).await;
    let grant = LocalTextGrant::approve_session_text();
    let mut client = server.client(grant.clone());
    let result = {
        let reply = client.reply("pending");
        tokio::pin!(reply);
        tokio::select! {
            result = &mut reply => panic!("unexpected result: {result:?}"),
            _ = server.fixture.started.notified() => {},
        }
        grant.revoke();
        server.fixture.continue_reply.notify_one();
        tokio::time::timeout(Duration::from_secs(1), reply)
            .await
            .unwrap()
    };
    assert!(matches!(result, Err(LocalConversationError::Revoked)));
    assert!(client.turns.is_empty());
    assert!(matches!(
        client.reply("new turn").await,
        Err(LocalConversationError::Revoked)
    ));
    assert_eq!(server.fixture.completions.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn response_bound_rejects_oversized_server_output_without_retaining_turn() {
    let server = serve(Behavior::Oversized).await;
    let mut client = server.client(LocalTextGrant::approve_session_text());
    assert!(matches!(
        client.reply("hello").await,
        Err(LocalConversationError::ResponseLimit)
    ));
    assert!(client.turns.is_empty());
}

#[tokio::test]
async fn tool_reply_is_rejected_as_untrusted_output() {
    let server = serve(Behavior::Tools).await;
    let mut client = server.client(LocalTextGrant::approve_session_text());
    assert!(matches!(
        client.reply("hello").await,
        Err(LocalConversationError::InvalidResponse)
    ));
    assert!(client.turns.is_empty());
}

#[tokio::test]
async fn actual_token_budget_blocks_generation_even_for_short_text() {
    let server = serve(Behavior::TooManyTokens).await;
    let mut client = server.client(LocalTextGrant::approve_session_text());
    assert!(matches!(
        client.reply("你好").await,
        Err(LocalConversationError::ContextLimit)
    ));
    assert_eq!(server.fixture.completions.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn whole_old_turns_are_removed_to_fit_context_and_history_stays_bounded() {
    let server = serve(Behavior::TrimHistory).await;
    let mut client = server.client(LocalTextGrant::approve_session_text());
    for _ in 0..6 {
        client.reply("hello").await.unwrap();
    }
    assert_eq!(client.turns.len(), 1);
    assert!(client.history_bytes() <= MAX_HISTORY_BYTES);
}

#[tokio::test]
async fn redirects_are_not_followed_or_retried() {
    let server = serve(Behavior::Redirect).await;
    let mut client = server.client(LocalTextGrant::approve_session_text());
    assert!(matches!(
        client.reply("private").await,
        Err(LocalConversationError::Unavailable)
    ));
    assert_eq!(server.fixture.calls.load(Ordering::SeqCst), 1);
}

#[test]
fn configuration_rejects_missing_port_or_credential() {
    assert!(matches!(
        LocalConversation::new(
            0,
            Zeroizing::new(TOKEN.into()),
            LocalTextGrant::approve_session_text()
        ),
        Err(LocalConversationError::InvalidConfiguration)
    ));
    assert!(matches!(
        LocalConversation::new(
            8080,
            Zeroizing::new("secret".into()),
            LocalTextGrant::approve_session_text()
        ),
        Err(LocalConversationError::InvalidConfiguration)
    ));
}
