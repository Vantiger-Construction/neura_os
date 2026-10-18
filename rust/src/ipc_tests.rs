use super::*;
use std::{
    pin::Pin,
    sync::atomic::{AtomicUsize, Ordering},
    task::{Context, Poll},
};
use tokio::{net::TcpStream, sync::Notify, time::timeout};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{client::IntoClientRequest, Error, Message as ClientMessage},
    MaybeTlsStream, WebSocketStream,
};

const TEST_TIMEOUT: Duration = Duration::from_secs(5);
type ClientSocket = WebSocketStream<MaybeTlsStream<TcpStream>>;

struct Server {
    address: SocketAddr,
    session: Session,
    _task: OwnedTask,
}

impl Server {
    async fn start() -> Self {
        Self::start_with(Adapter::Echo).await
    }

    async fn start_with(adapter: Adapter) -> Self {
        let session = Session::new("ab".repeat(32)).unwrap();
        let listener = bind_local("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let router = app_with(session.clone(), adapter);
        let task = tokio::spawn(async move {
            axum::serve(
                listener,
                router.into_make_service_with_connect_info::<SocketAddr>(),
            )
            .await
            .unwrap();
        });
        Self {
            address,
            session,
            _task: OwnedTask(task),
        }
    }

    fn request(&self, token: Option<&str>) -> axum::http::Request<()> {
        let mut request = format!("ws://{}/", self.address)
            .into_client_request()
            .unwrap();
        if let Some(token) = token {
            request.headers_mut().insert(
                header::AUTHORIZATION,
                format!("Bearer {token}").parse().unwrap(),
            );
        }
        request
    }

    async fn connect(&self) -> ClientSocket {
        timeout(
            TEST_TIMEOUT,
            connect_async(self.request(Some(&self.session.token))),
        )
        .await
        .unwrap()
        .unwrap()
        .0
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        self.session.revoke();
    }
}

async fn assert_rejected(request: axum::http::Request<()>, expected: StatusCode) {
    let result = timeout(TEST_TIMEOUT, connect_async(request)).await.unwrap();
    match result {
        Err(Error::Http(response)) => assert_eq!(response.status(), expected),
        _ => panic!("expected a rejected HTTP upgrade"),
    }
}

async fn send(socket: &mut ClientSocket, kind: &str, data: Value) {
    socket
        .send(ClientMessage::Text(
            json!({"v":1,"kind":kind,"data":data}).to_string(),
        ))
        .await
        .unwrap();
}

async fn receive(socket: &mut ClientSocket) -> Value {
    let message = timeout(TEST_TIMEOUT, socket.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let ClientMessage::Text(text) = message else {
        panic!("expected an envelope");
    };
    serde_json::from_str(&text).unwrap()
}

async fn assert_closed_without_completion(socket: &mut ClientSocket) {
    timeout(TEST_TIMEOUT, async {
        loop {
            match socket.next().await {
                Some(Ok(ClientMessage::Text(text))) => {
                    let value: Value = serde_json::from_str(&text).unwrap();
                    assert_ne!(value["kind"], "speak", "late completion after cancellation");
                }
                Some(Ok(ClientMessage::Close(_))) | Some(Err(_)) | None => break,
                _ => {}
            }
        }
    })
    .await
    .expect("cancelled connection must close promptly");
}

#[test]
fn envelope_has_frozen_contract() {
    let value: Value = serde_json::from_str(&frame("diagnostics", json!({}))).unwrap();
    assert_eq!(value["v"], 1);
    assert_eq!(value["kind"], "diagnostics");
    assert!(value["id"].as_str().is_some_and(|id| !id.is_empty()));
    assert!(value["data"].is_object());
}

#[test]
fn credential_configuration_fails_closed() {
    for token in [
        "".to_string(),
        "default".into(),
        "g".repeat(64),
        "ab".repeat(31),
    ] {
        assert!(Session::new(token).is_err());
    }
    assert!(Session::new("ab".repeat(32)).is_ok());
}

#[test]
fn only_numeric_loopback_addresses_are_accepted() {
    for address in ["127.0.0.1:8787", "127.0.0.2:0", "[::1]:8787"] {
        assert!(local_address(address).is_ok());
    }
    for address in [
        "0.0.0.0:8787",
        "[::]:8787",
        "192.168.1.10:8787",
        "8.8.8.8:8787",
        "[2001:db8::1]:8787",
        "[::ffff:192.168.1.10]:8787",
        "localhost:8787",
        "invalid",
    ] {
        assert!(local_address(address).is_err(), "{address}");
    }
}

#[tokio::test]
async fn non_loopback_binding_is_rejected_before_listen() {
    for address in ["0.0.0.0:0", "[::]:0", "192.168.1.10:0"] {
        let error = bind_local(address).await.unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::Other);
        assert_eq!(
            error.to_string(),
            "NEURA_API_ADDR must be a numeric loopback address"
        );
    }
    let listener = bind_local("127.0.0.1:0").await.unwrap();
    assert!(listener.local_addr().unwrap().ip().is_loopback());
}

#[tokio::test]
async fn unauthorized_websocket_clients_cannot_upgrade() {
    let server = Server::start().await;
    assert_rejected(server.request(None), StatusCode::UNAUTHORIZED).await;
    assert_rejected(
        server.request(Some(&"cd".repeat(32))),
        StatusCode::UNAUTHORIZED,
    )
    .await;

    let mut query_only = server.request(None);
    *query_only.uri_mut() = format!("ws://{}/?token={}", server.address, server.session.token)
        .parse()
        .unwrap();
    assert_rejected(query_only, StatusCode::UNAUTHORIZED).await;

    let mut duplicate = server.request(Some(&server.session.token));
    duplicate
        .headers_mut()
        .append(header::AUTHORIZATION, "Bearer invalid".parse().unwrap());
    assert_rejected(duplicate, StatusCode::UNAUTHORIZED).await;
    assert_eq!(server.session.clients.available_permits(), MAX_CLIENTS);
}

#[tokio::test]
async fn browser_origins_are_rejected_even_with_a_valid_token() {
    let server = Server::start().await;
    let mut request = server.request(Some(&server.session.token));
    request
        .headers_mut()
        .insert(header::ORIGIN, "https://example.invalid".parse().unwrap());
    assert_rejected(request, StatusCode::FORBIDDEN).await;
}

#[test]
fn non_loopback_peers_are_rejected_even_with_a_valid_token() {
    let session = Session::new("ab".repeat(32)).unwrap();
    let mut headers = HeaderMap::new();
    headers.insert(
        header::AUTHORIZATION,
        format!("Bearer {}", session.token).parse().unwrap(),
    );
    assert_eq!(
        session.authorize("192.168.1.10:1234".parse().unwrap(), &headers),
        Err(StatusCode::FORBIDDEN)
    );
}

#[tokio::test]
async fn authenticated_diagnostics_keep_the_degraded_echo_adapter() {
    let server = Server::start().await;
    let mut socket = server.connect().await;
    send(&mut socket, "hello", json!({})).await;
    let hello = receive(&mut socket).await;
    assert_eq!(hello["data"]["input_scope"], "synthetic-only");
    assert_eq!(hello["data"]["model_adapter"], "echo");

    send(&mut socket, "room_entered", json!({"room":"therapy"})).await;
    assert_eq!(receive(&mut socket).await["data"]["tone"], "calm");

    send(&mut socket, "diagnostics_request", json!({})).await;
    let diagnostics = receive(&mut socket).await;
    assert_eq!(diagnostics["kind"], "diagnostics");
    assert_eq!(diagnostics["data"]["model_mode"], "echo");
    assert!(diagnostics["data"].get("last_run").is_none());
    assert_eq!(diagnostics["data"]["checks"][2]["status"], "degraded");
    assert_eq!(
        diagnostics["data"]["checks"][2]["detail"],
        "Safe local echo provider is active."
    );
    assert!(!diagnostics
        .to_string()
        .contains(server.session.token.as_ref()));
}

#[tokio::test]
async fn only_fixed_synthetic_fixtures_can_generate_output() {
    let server = Server::start().await;
    let mut socket = server.connect().await;
    let unapproved = "DO-NOT-ECHO-THIS-UNAPPROVED-TEXT";
    for (kind, data) in [
        ("user_text", json!({"text":unapproved})),
        (
            "synthetic_input",
            json!({"fixture":"hello","text":unapproved}),
        ),
        ("synthetic_input", json!({"fixture":unapproved})),
    ] {
        send(&mut socket, kind, data).await;
        let response = receive(&mut socket).await;
        assert_eq!(response["kind"], "error");
        assert!(!response.to_string().contains(unapproved));
    }

    send(&mut socket, "synthetic_input", json!({"fixture":"hello"})).await;
    loop {
        let response = receive(&mut socket).await;
        assert!(matches!(
            response["kind"].as_str(),
            Some("speak_delta" | "speak")
        ));
        if response["kind"] == "speak" {
            assert_eq!(
                response["data"]["text"],
                "Local brain link is working. Synthetic input."
            );
            break;
        }
    }
}

#[tokio::test]
async fn cancel_closes_the_connection_without_a_late_completion_or_replay() {
    let server = Server::start().await;
    let mut socket = server.connect().await;
    send(&mut socket, "synthetic_input", json!({"fixture":"stream"})).await;
    assert_eq!(receive(&mut socket).await["kind"], "speak_delta");
    send(&mut socket, "cancel", json!({})).await;
    assert_closed_without_completion(&mut socket).await;

    let mut replacement = server.connect().await;
    send(&mut replacement, "diagnostics_request", json!({})).await;
    // A new connection starts with no previous generation or pending results.
    assert_eq!(receive(&mut replacement).await["kind"], "diagnostics");
}

#[tokio::test]
async fn revocation_requires_auth_and_ends_all_current_and_future_access() {
    let server = Server::start().await;
    let http = reqwest::Client::builder().no_proxy().build().unwrap();
    let endpoint = format!("http://{}/session/revoke", server.address);
    let unauthorized = http.post(&endpoint).send().await.unwrap();
    assert_eq!(unauthorized.status(), StatusCode::UNAUTHORIZED);
    assert!(server.session.is_active());

    let mut sockets = vec![server.connect().await, server.connect().await];
    for socket in &mut sockets {
        send(socket, "synthetic_input", json!({"fixture":"stream"})).await;
        assert_eq!(receive(socket).await["kind"], "speak_delta");
    }
    let result = http
        .post(&endpoint)
        .bearer_auth(server.session.token.as_ref())
        .send()
        .await
        .unwrap();
    assert_eq!(result.status(), StatusCode::NO_CONTENT);
    for socket in &mut sockets {
        assert_closed_without_completion(socket).await;
    }
    assert_rejected(
        server.request(Some(&server.session.token)),
        StatusCode::UNAUTHORIZED,
    )
    .await;
    assert_eq!(
        http.post(endpoint)
            .bearer_auth(server.session.token.as_ref())
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::UNAUTHORIZED
    );
}

#[tokio::test]
async fn connection_budget_is_bounded_and_released_on_close() {
    let server = Server::start().await;
    let mut sockets = Vec::new();
    for _ in 0..MAX_CLIENTS {
        sockets.push(server.connect().await);
    }
    assert_rejected(
        server.request(Some(&server.session.token)),
        StatusCode::TOO_MANY_REQUESTS,
    )
    .await;
    sockets.remove(0).close(None).await.unwrap();
    timeout(TEST_TIMEOUT, async {
        while server.session.clients.available_permits() == 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let mut replacement = server.connect().await;
    send(&mut replacement, "hello", json!({})).await;
    assert_eq!(receive(&mut replacement).await["kind"], "hello");
}

#[tokio::test]
async fn oversized_inbound_messages_close_the_connection() {
    let server = Server::start().await;
    let mut socket = server.connect().await;
    socket
        .send(ClientMessage::Text("x".repeat(MAX_MESSAGE_BYTES + 1)))
        .await
        .unwrap();
    assert_closed_without_completion(&mut socket).await;
}

#[tokio::test]
async fn full_closed_and_oversized_outbound_queues_fail_closed() {
    let session = Session::new("ab".repeat(32)).unwrap();
    let (out, receiver) = Outbound::new(session.clone());
    for _ in 0..OUTBOUND_CAPACITY {
        assert!(out.send("synthetic".into()));
    }
    assert!(!out.send("overflow".into()));
    assert!(!out.is_active());
    assert_eq!(receiver.len(), OUTBOUND_CAPACITY);
    assert!(!out.send("late output".into()));
    timeout(TEST_TIMEOUT, out.ended()).await.unwrap();

    let (out, receiver) = Outbound::new(session.clone());
    drop(receiver);
    assert!(!out.send("closed".into()));
    assert!(!out.is_active());

    let (out, receiver) = Outbound::new(session);
    assert!(!out.send("x".repeat(MAX_MESSAGE_BYTES + 1)));
    assert!(!out.is_active());
    assert_eq!(receiver.len(), 0);
}

// A transport that never becomes writable. No sleeps, OS socket-buffer sizes or
// racing network floods are needed to reproduce exhaustion during an active send.
struct StalledSink {
    polled: Arc<Notify>,
    sends: Arc<AtomicUsize>,
}

impl Sink<Message> for StalledSink {
    type Error = ();

    fn poll_ready(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<Result<(), ()>> {
        self.polled.notify_one();
        Poll::Pending
    }

    fn start_send(self: Pin<&mut Self>, _: Message) -> Result<(), ()> {
        self.sends.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }

    fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<Result<(), ()>> {
        Poll::Pending
    }

    fn poll_close(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<Result<(), ()>> {
        Poll::Ready(Ok(()))
    }
}

fn stalled_sink() -> (StalledSink, Arc<Notify>, Arc<AtomicUsize>) {
    let polled = Arc::new(Notify::new());
    let sends = Arc::new(AtomicUsize::new(0));
    (
        StalledSink {
            polled: polled.clone(),
            sends: sends.clone(),
        },
        polled,
        sends,
    )
}

#[tokio::test]
async fn queue_exhaustion_interrupts_stalled_delivery_and_stops_generation() {
    let (out, receiver) = Outbound::new(Session::new("ab".repeat(32)).unwrap());
    let (sink, polled, sends) = stalled_sink();
    assert!(out.send("first".into()));
    let mut writer = OwnedTask(tokio::spawn(write_outbound(sink, receiver, out.clone())));
    timeout(TEST_TIMEOUT, polled.notified()).await.unwrap();

    for _ in 0..OUTBOUND_CAPACITY {
        assert!(out.send("queued".into()));
    }
    let mut generation = spawn_echo(SyntheticFixture::Stream, out.clone());
    timeout(TEST_TIMEOUT, &mut generation.0)
        .await
        .unwrap()
        .unwrap();
    timeout(TEST_TIMEOUT, &mut writer.0).await.unwrap().unwrap();
    assert!(!out.is_active());
    assert!(out.sender.is_closed());
    assert_eq!(sends.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn cancellation_and_revocation_interrupt_stalled_writes() {
    for revoke in [false, true] {
        let session = Session::new("ab".repeat(32)).unwrap();
        let (out, receiver) = Outbound::new(session.clone());
        let (sink, polled, sends) = stalled_sink();
        assert!(out.send("pending".into()));
        let mut writer = OwnedTask(tokio::spawn(write_outbound(sink, receiver, out.clone())));
        timeout(TEST_TIMEOUT, polled.notified()).await.unwrap();
        if revoke {
            session.revoke();
        } else {
            out.stop();
        }
        timeout(TEST_TIMEOUT, &mut writer.0).await.unwrap().unwrap();
        assert!(out.sender.is_closed());
        assert!(!out.send("late".into()));
        assert_eq!(sends.load(Ordering::SeqCst), 0);
    }
}

#[tokio::test]
async fn stalled_transport_times_out_and_discards_the_queue() {
    let (out, receiver) = Outbound::new(Session::new("ab".repeat(32)).unwrap());
    let (sink, polled, sends) = stalled_sink();
    assert!(out.send("pending".into()));
    let mut writer = OwnedTask(tokio::spawn(write_outbound(sink, receiver, out.clone())));
    timeout(TEST_TIMEOUT, polled.notified()).await.unwrap();
    timeout(TEST_TIMEOUT, &mut writer.0).await.unwrap().unwrap();
    assert!(!out.is_active());
    assert!(out.sender.is_closed());
    assert_eq!(sends.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn revoked_session_discards_queued_results_before_writing() {
    let session = Session::new("ab".repeat(32)).unwrap();
    let (out, receiver) = Outbound::new(session.clone());
    assert!(out.send("queued result".into()));
    session.revoke();
    let (sink, _, sends) = stalled_sink();
    timeout(TEST_TIMEOUT, write_outbound(sink, receiver, out.clone()))
        .await
        .unwrap();
    assert_eq!(sends.load(Ordering::SeqCst), 0);
    assert!(out.sender.is_closed());
    assert!(!out.send("late result".into()));
}

#[tokio::test]
async fn failed_writer_closes_output_and_signals_the_owner() {
    let (out, receiver) = Outbound::new(Session::new("ab".repeat(32)).unwrap());
    assert!(out.send("pending".into()));
    let sink = Box::pin(futures_util::sink::unfold((), |(), _: Message| async {
        Err::<(), ()>(())
    }));
    timeout(TEST_TIMEOUT, write_outbound(sink, receiver, out.clone()))
        .await
        .unwrap();
    assert!(!out.is_active());
    assert!(out.sender.is_closed());
    timeout(TEST_TIMEOUT, out.ended()).await.unwrap();
}

#[tokio::test]
async fn aborted_writer_closes_output_and_signals_the_owner() {
    let (out, receiver) = Outbound::new(Session::new("ab".repeat(32)).unwrap());
    let (sink, polled, _) = stalled_sink();
    assert!(out.send("pending".into()));
    let writer = OwnedTask(tokio::spawn(write_outbound(sink, receiver, out.clone())));
    timeout(TEST_TIMEOUT, polled.notified()).await.unwrap();
    writer.stop().await;
    assert!(!out.is_active());
    assert!(out.sender.is_closed());
    timeout(TEST_TIMEOUT, out.ended()).await.unwrap();
}

#[tokio::test]
async fn owner_drop_aborts_instead_of_detaching_work() {
    struct Dropped(Option<tokio::sync::oneshot::Sender<()>>);
    impl Drop for Dropped {
        fn drop(&mut self) {
            if let Some(sender) = self.0.take() {
                let _ = sender.send(());
            }
        }
    }
    let (sender, receiver) = tokio::sync::oneshot::channel();
    let started = Arc::new(Notify::new());
    let notify = started.clone();
    let task = OwnedTask(tokio::spawn(async move {
        let _guard = Dropped(Some(sender));
        notify.notify_one();
        std::future::pending::<()>().await;
    }));
    timeout(TEST_TIMEOUT, started.notified()).await.unwrap();
    drop(task);
    timeout(TEST_TIMEOUT, receiver).await.unwrap().unwrap();
}

// ---- Milestone 2: opt-in pinned local model adapter -------------------------

struct DropFlag(Arc<std::sync::atomic::AtomicBool>);

impl Drop for DropFlag {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

/// Loopback stand-in for the operator's Ollama daemon.
struct MockOllama {
    endpoint: String,
    chats: Arc<AtomicUsize>,
    requests: Arc<Mutex<Vec<Value>>>,
    response_dropped: Arc<std::sync::atomic::AtomicBool>,
    _task: OwnedTask,
}

enum ChatBody {
    Lines(Vec<String>),
    /// One delta, then the response never completes.
    Hang,
}

fn ndjson(content: &str, done: bool) -> String {
    format!(
        "{}\n",
        json!({"message":{"role":"assistant","content":content},"done":done})
    )
}

fn pinned_info() -> Value {
    json!({"details":{"family":local_model::FAMILY,"parameter_size":local_model::PARAMETER_SIZE,
        "quantization_level":local_model::QUANTIZATION}})
}

impl MockOllama {
    async fn start(info: Value, body: ChatBody) -> Self {
        use axum::{body::Body, Json};
        let chats = Arc::new(AtomicUsize::new(0));
        let requests = Arc::new(Mutex::new(Vec::new()));
        let response_dropped = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let body = Arc::new(body);
        let (counter, seen, dropped) = (chats.clone(), requests.clone(), response_dropped.clone());
        let router = Router::new()
            .route(
                "/api/show",
                post(move |Json(request): Json<Value>| async move {
                    assert_eq!(request, json!({"model": local_model::MODEL}));
                    Json(info)
                }),
            )
            .route(
                "/api/chat",
                post(move |Json(request): Json<Value>| async move {
                    counter.fetch_add(1, Ordering::SeqCst);
                    seen.lock().unwrap().push(request);
                    match &*body {
                        ChatBody::Lines(lines) => Body::from(lines.concat()),
                        ChatBody::Hang => {
                            let guard = DropFlag(dropped);
                            let first = futures_util::stream::once(async {
                                Ok::<_, std::io::Error>(ndjson("Thinking ", false))
                            });
                            Body::from_stream(first.chain(futures_util::stream::pending()).map(
                                move |item| {
                                    let _ = &guard;
                                    item
                                },
                            ))
                        }
                    }
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        Self {
            endpoint,
            chats,
            requests,
            response_dropped,
            _task: OwnedTask(task),
        }
    }

    fn adapter(&self) -> (Adapter, Arc<LocalAdapter>) {
        let local = Arc::new(LocalAdapter::new(self.endpoint.clone(), || true));
        (Adapter::Local(local.clone()), local)
    }
}

/// Collect a run's frames until its terminal `speak` or `error`.
async fn run_fixture(socket: &mut ClientSocket, fixture: &str) -> (String, Value) {
    send(socket, "synthetic_input", json!({"fixture":fixture})).await;
    let mut deltas = String::new();
    loop {
        let response = receive(socket).await;
        match response["kind"].as_str() {
            Some("speak_delta") => deltas.push_str(response["data"]["delta"].as_str().unwrap()),
            Some("speak" | "error") => return (deltas, response),
            other => panic!("unexpected frame {other:?}"),
        }
    }
}

#[test]
fn adapter_selection_is_explicit_and_fails_closed() {
    assert!(matches!(Adapter::from_setting(None), Ok(Adapter::Echo)));
    assert!(matches!(
        Adapter::from_setting(Some("echo")),
        Ok(Adapter::Echo)
    ));
    assert!(matches!(
        Adapter::from_setting(Some("ollama-local")),
        Ok(Adapter::Local(_))
    ));
    for value in [
        "",
        "ollama",
        "OLLAMA-LOCAL",
        "cloud",
        "http://127.0.0.1:11434",
    ] {
        assert!(Adapter::from_setting(Some(value)).is_err());
    }
}

#[tokio::test]
async fn verified_local_model_streams_fixed_fixture_and_reports_content_free_metrics() {
    let model_text = "The local Neura engine link works.";
    let ollama = MockOllama::start(
        pinned_info(),
        ChatBody::Lines(vec![
            ndjson("The local ", false),
            ndjson("Neura engine ", false),
            ndjson("link works.", false),
            ndjson("", true),
        ]),
    )
    .await;
    let (adapter, _) = ollama.adapter();
    let server = Server::start_with(adapter).await;
    let mut socket = server.connect().await;

    send(&mut socket, "hello", json!({})).await;
    assert_eq!(
        receive(&mut socket).await["data"]["model_adapter"],
        "ollama-local"
    );
    send(&mut socket, "diagnostics_request", json!({})).await;
    let diagnostics = receive(&mut socket).await;
    assert_eq!(diagnostics["data"]["model_mode"], "local");
    assert_eq!(diagnostics["data"]["input_scope"], "synthetic-only");
    assert_eq!(diagnostics["data"]["checks"][2]["status"], "ok");
    assert_eq!(
        diagnostics["data"]["model"]["quantization"],
        local_model::QUANTIZATION
    );
    assert!(diagnostics["data"]["last_run"].is_null());

    let (deltas, done) = run_fixture(&mut socket, "hello").await;
    assert_eq!(done["kind"], "speak");
    assert_eq!(done["data"]["text"], model_text);
    assert_eq!(deltas, model_text);

    // Only the fixed, repository-defined prompt reached the model.
    let request = ollama.requests.lock().unwrap()[0].clone();
    assert_eq!(request["model"], local_model::LOCAL_MODEL);
    assert_eq!(request["keep_alive"], 0);
    assert_eq!(request["stream"], true);
    assert!(request.get("tools").is_none());
    assert_eq!(
        request["messages"][1]["content"],
        SyntheticFixture::Hello.model_prompt()
    );

    send(&mut socket, "diagnostics_request", json!({})).await;
    let diagnostics = receive(&mut socket).await;
    let last = &diagnostics["data"]["last_run"];
    assert_eq!(last["fixture"], "hello");
    assert_eq!(last["outcome"], "completed");
    assert_eq!(last["output_bytes"], model_text.len());
    assert!(last["ttft_ms"].is_u64() && last["total_ms"].is_u64());
    // Metrics never carry model output or the prompt.
    let text = diagnostics.to_string();
    assert!(!text.contains("engine link works"));
    assert!(!text.contains(SyntheticFixture::Hello.model_prompt()));
    assert!(!text.contains(server.session.token.as_ref()));
}

#[tokio::test]
async fn unverifiable_models_are_unavailable_with_no_fallback_or_prompt_submission() {
    let mut remote = pinned_info();
    remote["remote_host"] = json!("https://ollama.com");
    let mut wrong = pinned_info();
    wrong["details"]["parameter_size"] = json!("8.0B");
    for (info, code) in [(remote, "remote_model"), (wrong, "model_mismatch")] {
        let ollama = MockOllama::start(info, ChatBody::Lines(vec![ndjson("leak", true)])).await;
        let (adapter, local) = ollama.adapter();
        let server = Server::start_with(adapter).await;
        let mut socket = server.connect().await;

        send(&mut socket, "diagnostics_request", json!({})).await;
        let diagnostics = receive(&mut socket).await;
        assert_eq!(diagnostics["data"]["model_mode"], "unavailable");
        assert_eq!(diagnostics["data"]["checks"][2]["status"], "unavailable");
        assert_eq!(diagnostics["data"]["checks"][2]["code"], code);

        let (deltas, response) = run_fixture(&mut socket, "hello").await;
        assert!(deltas.is_empty());
        assert_eq!(response["kind"], "error");
        assert_eq!(response["data"]["code"], code);
        assert_eq!(ollama.chats.load(Ordering::SeqCst), 0);
        assert_eq!(local.last_run().unwrap().outcome, "unavailable");
    }
}

#[tokio::test]
async fn absent_daemon_and_memory_budget_fail_closed() {
    // Nothing listens on loopback port 1.
    let absent = Arc::new(LocalAdapter::new("http://127.0.0.1:1".into(), || true));
    assert_eq!(absent.probe().await, Err(ModelUnavailable::Unreachable));

    let ollama = MockOllama::start(pinned_info(), ChatBody::Lines(vec![ndjson("x", true)])).await;
    let starved = Arc::new(LocalAdapter::new(ollama.endpoint.clone(), || false));
    let server = Server::start_with(Adapter::Local(starved)).await;
    let mut socket = server.connect().await;
    let (_, response) = run_fixture(&mut socket, "stream").await;
    assert_eq!(response["data"]["code"], "insufficient_memory");
    assert_eq!(ollama.chats.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn cancel_aborts_the_in_flight_model_request() {
    let ollama = MockOllama::start(pinned_info(), ChatBody::Hang).await;
    let (adapter, local) = ollama.adapter();
    let server = Server::start_with(adapter).await;
    let mut socket = server.connect().await;
    send(&mut socket, "synthetic_input", json!({"fixture":"stream"})).await;
    // The first delta is delivered immediately even though it is tiny.
    let first = receive(&mut socket).await;
    assert_eq!(first["kind"], "speak_delta");
    assert!(!ollama.response_dropped.load(Ordering::SeqCst));

    send(&mut socket, "cancel", json!({})).await;
    assert_closed_without_completion(&mut socket).await;
    timeout(TEST_TIMEOUT, async {
        while !ollama.response_dropped.load(Ordering::SeqCst) {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("cancelling must drop the model response stream");
    assert_eq!(local.last_run().unwrap().outcome, "cancelled");

    // Revocation likewise stops a hung request for every client.
    let mut replacement = server.connect().await;
    send(
        &mut replacement,
        "synthetic_input",
        json!({"fixture":"hello"}),
    )
    .await;
    assert_eq!(receive(&mut replacement).await["kind"], "speak_delta");
    server.session.revoke();
    assert_closed_without_completion(&mut replacement).await;
}

#[tokio::test]
async fn overlong_or_incomplete_model_output_is_rejected_without_completion() {
    for (lines, message) in [
        (
            vec![ndjson(&"x".repeat(MAX_MODEL_OUTPUT + 1), true)],
            "model output exceeded budget",
        ),
        (vec![ndjson("partial", false)], "model request failed"),
        (
            vec![format!(
                "{}\n",
                json!({"message":{"role":"assistant","content":"x","tool_calls":[{}]},"done":true})
            )],
            "model request failed",
        ),
    ] {
        let ollama = MockOllama::start(pinned_info(), ChatBody::Lines(lines)).await;
        let (adapter, _) = ollama.adapter();
        let server = Server::start_with(adapter).await;
        let mut socket = server.connect().await;
        let (_, response) = run_fixture(&mut socket, "hello").await;
        assert_eq!(response["kind"], "error");
        assert_eq!(response["data"]["message"], message);
    }
}

#[tokio::test]
async fn overlapping_local_work_and_diagnostics_are_rejected_not_queued() {
    let ollama = MockOllama::start(pinned_info(), ChatBody::Hang).await;
    let (adapter, _) = ollama.adapter();
    let server = Server::start_with(adapter).await;
    let mut socket = server.connect().await;
    send(&mut socket, "synthetic_input", json!({"fixture":"stream"})).await;
    assert_eq!(receive(&mut socket).await["kind"], "speak_delta");
    send(&mut socket, "synthetic_input", json!({"fixture":"hello"})).await;
    let response = receive(&mut socket).await;
    assert_eq!(response["data"]["message"], "synthetic work already active");
    assert_eq!(ollama.chats.load(Ordering::SeqCst), 1);
}
