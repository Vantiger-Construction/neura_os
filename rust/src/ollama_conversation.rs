//! Opt-in Windows chat adapter. The operator owns the separately installed
//! Ollama daemon; Neura owns only its cancellable request, never that process.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    sync::{Arc, Mutex, OnceLock},
    thread::JoinHandle,
    time::Duration,
};
use tokio::sync::watch;
use zeroize::Zeroizing;

use crate::local_model::{bounded_json, memory_admitted, ENDPOINT, LOCAL_MODEL};
const MAX_REQUEST: usize = 16_384;
const MAX_RESPONSE: usize = 32_768;
const MAX_REPLY: usize = 8_192;

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Turn {
    role: String,
    content: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    system: String,
    messages: Vec<Turn>,
}

fn prepare(raw: &[u8]) -> Result<Value, ()> {
    let request: Request = serde_json::from_slice(raw).map_err(|_| ())?;
    if request.system.is_empty()
        || request.system.len() > 6_500
        || request.messages.is_empty()
        || request.messages.len() > 64
        || request.messages.last().map(|t| t.role.as_str()) != Some("user")
        || request
            .messages
            .iter()
            .any(|t| !matches!(t.role.as_str(), "user" | "assistant"))
    {
        return Err(());
    }
    // Retain whole recent turns, never truncate the charter or newest message.
    // A short byte budget complements Ollama's hard 2048-token context limit.
    let mut retained = Vec::new();
    let mut bytes = 0;
    for turn in request.messages.into_iter().rev().take(8) {
        if bytes + turn.content.len() > 1_500 {
            if retained.is_empty() {
                return Err(());
            }
            break;
        }
        bytes += turn.content.len();
        retained.push(turn);
    }
    retained.reverse();
    while retained.first().is_some_and(|t| t.role != "user") {
        retained.remove(0);
    }
    let mut messages = vec![json!({"role":"system", "content": request.system})];
    messages.extend(retained.into_iter().map(|t| json!(t)));
    Ok(
        json!({"model": LOCAL_MODEL, "messages": messages, "stream": false,
        "keep_alive": 0, "options": {"num_ctx":2048,"num_predict":256,
        "num_thread":2,"temperature":0.6}}),
    )
}

async fn inference(endpoint: &str, payload: Value) -> Result<String, ()> {
    let client = crate::local_model::LoopbackClient::new(endpoint, Duration::from_secs(90))?;
    // Fail before submitting conversation text if this tag is a remote model
    // or has been replaced with a different family/size/quantization.
    crate::local_model::verify_pinned_model(&client)
        .await
        .map_err(|_| ())?;
    let response = bounded_json(
        client
            .post_json("/api/chat", &payload)
            .send()
            .await
            .map_err(|_| ())?,
        MAX_RESPONSE,
    )
    .await?;
    let message = &response["message"];
    if response.get("remote_host").is_some()
        || response.get("remote_model").is_some()
        || response["done"] != true
        || message["role"] != "assistant"
        || message
            .get("tool_calls")
            .is_some_and(|v| !v.as_array().is_some_and(|a| a.is_empty()))
    {
        return Err(());
    }
    let text = message["content"].as_str().ok_or(())?;
    if text.trim().is_empty() || text.len() > MAX_REPLY {
        return Err(());
    }
    Ok(text.to_owned())
}

#[derive(Default)]
struct State {
    generation: i64,
    foreground: bool,
    blocked: bool,
    status: i32,
    reply: Option<Zeroizing<Vec<u8>>>,
}
struct Active {
    cancel: watch::Sender<bool>,
    worker: JoinHandle<()>,
}
#[derive(Default)]
struct Session {
    state: Arc<Mutex<State>>,
    active: Option<Active>,
}
impl Session {
    fn cancel(&mut self) {
        let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
        state.generation += 1;
        state.reply = None;
        state.status = -2;
        if let Some(active) = &self.active {
            active.cancel.send_replace(true);
        }
    }
    fn begin(&mut self, payload: Value) -> i64 {
        {
            let state = self.state.lock().unwrap_or_else(|p| p.into_inner());
            if state.blocked || !state.foreground {
                return -2;
            }
        }
        if !memory_admitted() {
            return -4;
        }
        if self
            .active
            .as_ref()
            .is_some_and(|a| !a.worker.is_finished())
        {
            return -3;
        }
        if let Some(active) = self.active.take() {
            let _ = active.worker.join();
        }
        self.cancel();
        let generation = {
            let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
            state.status = 0;
            state.generation
        };
        let (cancel, mut receiver) = watch::channel(false);
        let state = self.state.clone();
        let worker = std::thread::Builder::new().name("neura-ollama".into()).spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().map_err(|_| ())?;
                tracing::subscriber::with_default(tracing::subscriber::NoSubscriber::default(), || runtime.block_on(async {
                    tokio::select! { biased;
                        _ = receiver.changed() => Err(()),
                        result = tokio::time::timeout(Duration::from_secs(90), inference(ENDPOINT, payload)) => result.map_err(|_| ())?,
                    }
                }))
            }));
            let mut state = state.lock().unwrap_or_else(|p| p.into_inner());
            if generation != state.generation || state.blocked || !state.foreground { return; }
            match result {
                Ok(Ok(text)) => { state.reply = Some(Zeroizing::new(text.into_bytes())); state.status = 1; }
                _ => state.status = -1,
            }
        });
        match worker {
            Ok(worker) => {
                self.active = Some(Active { cancel, worker });
                generation
            }
            Err(_) => {
                self.state.lock().unwrap_or_else(|p| p.into_inner()).status = -1;
                -1
            }
        }
    }
}
fn session() -> &'static Mutex<Session> {
    static SESSION: OnceLock<Mutex<Session>> = OnceLock::new();
    SESSION.get_or_init(|| Mutex::new(Session::default()))
}

/// # Safety
/// `data` must point to `len` readable bytes for this synchronous call.
#[no_mangle]
pub unsafe extern "C" fn neura_ollama_begin(data: *const u8, len: usize) -> i64 {
    if data.is_null() || len == 0 || len > MAX_REQUEST {
        return -1;
    }
    // SAFETY: the native owner supplies its live std::string allocation.
    let raw = unsafe { std::slice::from_raw_parts(data, len) };
    let Ok(payload) = prepare(raw) else {
        return -1;
    };
    session()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .begin(payload)
}
/// # Safety
/// `buffer` must point to `capacity` writable bytes for this synchronous call.
#[no_mangle]
pub unsafe extern "C" fn neura_ollama_poll(id: i64, buffer: *mut u8, capacity: usize) -> i32 {
    let session = session().lock().unwrap_or_else(|p| p.into_inner());
    let mut state = session.state.lock().unwrap_or_else(|p| p.into_inner());
    if id != state.generation || state.blocked || !state.foreground {
        return -2;
    }
    if state.status != 1 {
        return state.status;
    }
    let Some(reply) = state.reply.as_ref() else {
        return -1;
    };
    if buffer.is_null() || capacity < reply.len() {
        return -1;
    }
    let len = reply.len();
    // SAFETY: caller provides a separate, sufficiently sized output buffer.
    unsafe {
        std::ptr::copy_nonoverlapping(reply.as_ptr(), buffer, len);
    }
    state.reply = None;
    state.status = -2;
    len as i32
}
#[no_mangle]
pub extern "C" fn neura_ollama_cancel(id: i64) {
    let mut session = session().lock().unwrap_or_else(|p| p.into_inner());
    let current = session
        .state
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .generation;
    if id == current {
        session.cancel();
    }
}
#[no_mangle]
pub extern "C" fn neura_ollama_foreground(value: i32) {
    let mut session = session().lock().unwrap_or_else(|p| p.into_inner());
    session
        .state
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .foreground = value == 1;
    if value != 1 {
        session.cancel();
    }
}
#[no_mangle]
pub extern "C" fn neura_ollama_block() {
    let mut session = session().lock().unwrap_or_else(|p| p.into_inner());
    session
        .state
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .blocked = true;
    session.cancel();
}

/// Join the request worker before the owning DLL handle can be released.
#[no_mangle]
pub extern "C" fn neura_ollama_shutdown() {
    let mut session = session().lock().unwrap_or_else(|p| p.into_inner());
    session
        .state
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .blocked = true;
    session.cancel();
    if let Some(active) = session.active.take() {
        let _ = active.worker.join();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fixes_model_and_resource_limits_and_preserves_system() {
        let payload = prepare(
            br#"{"system":"Neura charter","messages":[{"role":"user","content":"Hello"}]}"#,
        )
        .unwrap();
        assert_eq!(payload["model"], LOCAL_MODEL);
        assert_eq!(payload["messages"][0]["content"], "Neura charter");
        assert_eq!(payload["options"]["num_ctx"], 2048);
        assert_eq!(payload["keep_alive"], 0);
        assert!(payload.get("tools").is_none());
    }
    #[test]
    fn rejects_tools_images_endpoints_and_large_current_turn() {
        for raw in [
            r#"{"system":"x","messages":[{"role":"tool","content":"x"}]}"#,
            r#"{"system":"x","messages":[{"role":"user","content":"x","images":[]}]}"#,
            r#"{"system":"x","messages":[{"role":"user","content":"x"}],"endpoint":"https://example.com"}"#,
        ] {
            assert!(prepare(raw.as_bytes()).is_err());
        }
        assert!(prepare(
            json!({"system":"x","messages":[{"role":"user","content":"x".repeat(1501)}]})
                .to_string()
                .as_bytes()
        )
        .is_err());
    }
    #[test]
    fn background_and_block_prevent_admission_and_clear_reply() {
        let mut s = Session::default();
        assert_eq!(s.begin(json!({})), -2);
        {
            let mut state = s.state.lock().unwrap();
            state.foreground = true;
            state.blocked = true;
            state.reply = Some(Zeroizing::new(b"private".to_vec()));
        }
        s.cancel();
        assert!(s.state.lock().unwrap().reply.is_none());
        assert_eq!(s.begin(json!({})), -2);
    }

    #[test]
    fn stale_cancel_cannot_wipe_a_replacement_and_revoked_reply_cannot_be_read() {
        {
            let s = session().lock().unwrap();
            let mut state = s.state.lock().unwrap();
            state.generation = 99;
            state.foreground = true;
            state.blocked = false;
            state.status = 1;
            state.reply = Some(Zeroizing::new(b"reply".to_vec()));
        }
        neura_ollama_cancel(98);
        let mut buffer = [0u8; 8];
        // SAFETY: buffer is live and its advertised capacity is its size.
        assert_eq!(
            unsafe { neura_ollama_poll(98, buffer.as_mut_ptr(), buffer.len()) },
            -2
        );
        assert!(session()
            .lock()
            .unwrap()
            .state
            .lock()
            .unwrap()
            .reply
            .is_some());
        neura_ollama_cancel(99);
        // SAFETY: buffer is live and its advertised capacity is its size.
        assert_eq!(
            unsafe { neura_ollama_poll(99, buffer.as_mut_ptr(), buffer.len()) },
            -2
        );
        assert_eq!(buffer, [0; 8]);
        assert!(session()
            .lock()
            .unwrap()
            .state
            .lock()
            .unwrap()
            .reply
            .is_none());
    }

    fn local_info() -> Value {
        crate::local_model::tests::pinned_info()
    }
    fn payload() -> Value {
        prepare(br#"{"system":"Neura charter","messages":[{"role":"user","content":"Hello"}]}"#)
            .unwrap()
    }
    async fn mock(
        info: Value,
        answer: Value,
    ) -> (
        String,
        std::sync::Arc<std::sync::atomic::AtomicUsize>,
        tokio::task::JoinHandle<()>,
    ) {
        use axum::{routing::post, Json};
        use std::sync::atomic::{AtomicUsize, Ordering};
        let calls = Arc::new(AtomicUsize::new(0));
        let counter = calls.clone();
        let router = crate::local_model::tests::metadata_router()
            .route("/api/show", post(move || async move { Json(info) }))
            .route(
                "/api/chat",
                post(move |Json(request): Json<Value>| async move {
                    counter.fetch_add(1, Ordering::SeqCst);
                    assert_eq!(request["model"], LOCAL_MODEL);
                    assert_eq!(request["keep_alive"], 0);
                    assert!(request.get("tools").is_none());
                    Json(answer)
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        (endpoint, calls, task)
    }
    #[tokio::test]
    async fn local_http_conversation_and_remote_model_rejection() {
        use std::sync::atomic::Ordering;
        let answer = json!({"done":true,"message":{"role":"assistant","content":"Hi, I'm Neura."}});
        let (endpoint, calls, task) = mock(local_info(), answer.clone()).await;
        assert_eq!(
            inference(&endpoint, payload()).await.unwrap(),
            "Hi, I'm Neura."
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        task.abort();
        let mut info = local_info();
        info["remote_host"] = json!("https://ollama.com");
        let (endpoint, calls, task) = mock(info, answer).await;
        assert!(inference(&endpoint, payload()).await.is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        task.abort();
    }
    #[tokio::test]
    async fn rejects_tool_calls_incomplete_and_oversized_replies() {
        for answer in [
            json!({"done":true,"message":{"role":"assistant","content":"x","tool_calls":[{}]}}),
            json!({"done":false,"message":{"role":"assistant","content":"x"}}),
            json!({"done":true,"message":{"role":"assistant","content":"x".repeat(MAX_REPLY+1)}}),
            json!({"done":true,"message":{"role":"assistant","content":"x".repeat(MAX_RESPONSE+1)}}),
        ] {
            let (endpoint, _, task) = mock(local_info(), answer).await;
            assert!(inference(&endpoint, payload()).await.is_err());
            task.abort();
        }
    }
    #[tokio::test]
    async fn never_follows_redirects() {
        use axum::{response::Redirect, routing::post};
        let router = crate::local_model::tests::metadata_router().route(
            "/api/show",
            post(|| async { Redirect::temporary("http://127.0.0.1:1/forbidden") }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        assert!(inference(&endpoint, payload()).await.is_err());
        task.abort();
    }
}
