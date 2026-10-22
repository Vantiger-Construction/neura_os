//! Opt-in Windows chat adapter. The operator owns the separately installed
//! Ollama daemon; Neura owns only its cancellable request, never that process.
use crate::ollama_latency::{RequestTiming, TIMING_FIELDS};
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
        json!({"model": LOCAL_MODEL, "messages": messages, "stream": false, "think": false,
        "keep_alive": 0, "options": {"num_ctx":2048,"num_predict":256,
        "num_thread":2,"temperature":0.6}}),
    )
}

#[cfg(test)]
async fn inference(endpoint: &str, payload: Value) -> Result<String, ()> {
    timed_inference(endpoint, payload, &Mutex::new(RequestTiming::default())).await
}

async fn timed_inference(
    endpoint: &str,
    payload: Value,
    timing: &Mutex<RequestTiming>,
) -> Result<String, ()> {
    let client = crate::local_model::LoopbackClient::new(endpoint, Duration::from_secs(90))?;
    // Fail before submitting conversation text if this tag is a remote model
    // or has been replaced with a different family/size/quantization.
    crate::local_model::verify_pinned_model(&client)
        .await
        .map_err(|_| ())?;
    timing
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .preflight_done();
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

async fn cancellable_inference(
    endpoint: &str,
    payload: Value,
    timing: &Mutex<RequestTiming>,
    receiver: &mut watch::Receiver<bool>,
) -> Result<String, ()> {
    tokio::select! { biased;
        _ = receiver.changed() => Err(()),
        result = tokio::time::timeout(Duration::from_secs(90), timed_inference(endpoint, payload, timing)) => result.map_err(|_| ())?,
    }
}

#[derive(Default)]
struct State {
    generation: i64,
    foreground: bool,
    blocked: bool,
    status: i32,
    reply: Option<Zeroizing<Vec<u8>>>,
    timing: Option<(i64, Arc<Mutex<RequestTiming>>)>,
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
        if let Some((_, timing)) = &state.timing {
            timing.lock().unwrap_or_else(|p| p.into_inner()).cancel();
        }
        state.generation += 1;
        state.reply = None;
        state.status = -2;
        if let Some(active) = &self.active {
            active.cancel.send_replace(true);
        }
    }
    fn begin(&mut self, payload: Value) -> i64 {
        self.begin_checked(payload, memory_admitted)
    }
    fn begin_checked(&mut self, payload: Value, admit_memory: impl FnOnce() -> bool) -> i64 {
        {
            let state = self.state.lock().unwrap_or_else(|p| p.into_inner());
            if state.blocked || !state.foreground {
                return -2;
            }
        }
        if !admit_memory() {
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
        let timing = Arc::new(Mutex::new(RequestTiming::default()));
        let generation = {
            let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
            state.status = 0;
            state.timing = Some((state.generation, timing.clone()));
            state.generation
        };
        let (cancel, mut receiver) = watch::channel(false);
        let state = self.state.clone();
        let worker = std::thread::Builder::new()
            .name("neura-ollama".into())
            .spawn(move || {
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    let runtime = tokio::runtime::Builder::new_current_thread()
                        .enable_all()
                        .build()
                        .map_err(|_| ())?;
                    tracing::subscriber::with_default(
                        tracing::subscriber::NoSubscriber::default(),
                        || {
                            runtime.block_on(cancellable_inference(
                                ENDPOINT,
                                payload,
                                &timing,
                                &mut receiver,
                            ))
                        },
                    )
                }));
                let mut state = state.lock().unwrap_or_else(|p| p.into_inner());
                timing
                    .lock()
                    .unwrap_or_else(|p| p.into_inner())
                    .worker_done(matches!(&result, Ok(Ok(_))));
                if generation != state.generation || state.blocked || !state.foreground {
                    return;
                }
                match result {
                    Ok(Ok(text)) => {
                        state.reply = Some(Zeroizing::new(text.into_bytes()));
                        state.status = 1;
                    }
                    _ => state.status = -1,
                }
            });
        match worker {
            Ok(worker) => {
                self.active = Some(Active { cancel, worker });
                generation
            }
            Err(_) => {
                let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
                state.status = -1;
                if let Some((_, timing)) = &state.timing {
                    timing
                        .lock()
                        .unwrap_or_else(|p| p.into_inner())
                        .worker_done(false);
                }
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
    if let Some((_, timing)) = &state.timing {
        timing.lock().unwrap_or_else(|p| p.into_inner()).delivered();
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

/// Read the latest numeric request timing without starting or waiting for work.
/// A cancelled request keeps its original id solely for a foreground read.
/// # Safety
/// `buffer` must point to `capacity` aligned, writable u64 elements.
#[no_mangle]
pub unsafe extern "C" fn neura_ollama_timing(id: i64, buffer: *mut u64, capacity: usize) -> i32 {
    if buffer.is_null() || capacity < TIMING_FIELDS {
        return 0;
    }
    let session = session().lock().unwrap_or_else(|p| p.into_inner());
    let state = session.state.lock().unwrap_or_else(|p| p.into_inner());
    if state.blocked || !state.foreground {
        return 0;
    }
    let Some((request_id, timing)) = &state.timing else {
        return 0;
    };
    if *request_id != id {
        return 0;
    }
    let values = timing.lock().unwrap_or_else(|p| p.into_inner()).snapshot();
    // SAFETY: caller supplies a separate, aligned buffer with sufficient space.
    unsafe {
        std::ptr::copy_nonoverlapping(values.as_ptr(), buffer, TIMING_FIELDS);
    }
    TIMING_FIELDS as i32
}

#[no_mangle]
pub extern "C" fn neura_ollama_clear_timing() {
    session()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .state
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .timing = None;
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
        session
            .state
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .timing = None;
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
    session
        .state
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .timing = None;
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
    session
        .state
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .timing = None;
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
        assert_eq!(payload["think"], false);
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
    fn memory_rejection_creates_neither_worker_nor_timing() {
        let mut s = Session::default();
        s.state.lock().unwrap().foreground = true;
        assert_eq!(s.begin_checked(json!({}), || false), -4);
        assert!(s.active.is_none());
        assert!(s.state.lock().unwrap().timing.is_none());
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
            let mut timing = RequestTiming::default();
            timing.preflight_done();
            timing.worker_done(true);
            state.timing = Some((99, Arc::new(Mutex::new(timing))));
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
        let mut values = [0u64; TIMING_FIELDS];
        // SAFETY: all timing calls below advertise this live aligned array.
        unsafe {
            assert_eq!(
                neura_ollama_timing(98, values.as_mut_ptr(), values.len()),
                0
            );
            assert_eq!(
                neura_ollama_timing(99, std::ptr::null_mut(), values.len()),
                0
            );
            assert_eq!(neura_ollama_timing(99, values.as_mut_ptr(), 1), 0);
            assert_eq!(
                neura_ollama_timing(99, values.as_mut_ptr(), values.len()),
                7
            );
        }
        assert_eq!(values[1], 3); // Cancellation of ready reply, no delivery.
        assert_eq!(values[4], u64::MAX);
        neura_ollama_foreground(0);
        neura_ollama_foreground(1);
        // SAFETY: same live output array; backgrounding erased the record.
        assert_eq!(
            unsafe { neura_ollama_timing(99, values.as_mut_ptr(), values.len()) },
            0
        );
        {
            let s = session().lock().unwrap();
            s.state.lock().unwrap().timing =
                Some((100, Arc::new(Mutex::new(RequestTiming::default()))));
        }
        neura_ollama_block();
        assert!(session()
            .lock()
            .unwrap()
            .state
            .lock()
            .unwrap()
            .timing
            .is_none());
        // Reset the test fixture without reopening a real blocked session.
        *session().lock().unwrap() = Session::default();
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
                    assert_eq!(request["think"], false);
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
    async fn cancelling_stalled_inference_finishes_without_delivery() {
        use axum::{routing::post, Json};
        let (reached, mut observed) = watch::channel(false);
        let router = crate::local_model::tests::metadata_router()
            .route("/api/show", post(|| async { Json(local_info()) }))
            .route(
                "/api/chat",
                post(move || async move {
                    reached.send_replace(true);
                    std::future::pending::<Json<Value>>().await
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        let timing = Arc::new(Mutex::new(RequestTiming::default()));
        let worker_timing = timing.clone();
        let (cancel, mut receiver) = watch::channel(false);
        let request = tokio::spawn(async move {
            let result =
                cancellable_inference(&endpoint, payload(), &worker_timing, &mut receiver).await;
            worker_timing.lock().unwrap().worker_done(result.is_ok());
            result
        });
        // Synchronize on entry to inference, never on an arbitrary sleep.
        tokio::time::timeout(Duration::from_secs(2), observed.changed())
            .await
            .unwrap()
            .unwrap();
        timing.lock().unwrap().cancel();
        cancel.send_replace(true);
        assert!(tokio::time::timeout(Duration::from_secs(2), request)
            .await
            .unwrap()
            .unwrap()
            .is_err());
        let values = timing.lock().unwrap().snapshot();
        assert_eq!(values[1], 3);
        assert_ne!(values[2], u64::MAX);
        assert_ne!(values[3], u64::MAX);
        assert_eq!(values[4], u64::MAX);
        assert_ne!(values[5], u64::MAX);
        server.abort();
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
    async fn rejects_advertised_oversize_without_waiting_for_body() {
        use axum::{body::Body, http::Response, routing::get, Router};
        let router = Router::new().route(
            "/",
            get(|| async {
                let body = Body::from_stream(futures_util::stream::pending::<
                    Result<String, std::io::Error>,
                >());
                Response::builder()
                    .header("content-length", "1000000")
                    .body(body)
                    .unwrap()
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        let response = reqwest::Client::builder()
            .no_proxy()
            .build()
            .unwrap()
            .get(endpoint)
            .send()
            .await
            .unwrap();
        let result =
            tokio::time::timeout(Duration::from_secs(2), bounded_json(response, MAX_RESPONSE))
                .await;
        task.abort();
        assert!(result.unwrap().is_err());
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
