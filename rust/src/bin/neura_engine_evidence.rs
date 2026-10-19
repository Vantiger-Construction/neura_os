//! Collect content-free milestone 2 evidence for the pinned local model on the
//! operator's own machine. Explicit, foreground, developer-run tool: it is not
//! bundled with the app, never downloads or starts a model, and never records
//! prompt or model text. See docs/NEURA_ENGINE_MODEL_ADAPTER_M2.md.
//!
//! cargo run --release --manifest-path rust/Cargo.toml --bin neura_engine_evidence -- \
//!     --confirm-local-model [--runs 3] [--out evidence.json]
use futures_util::{SinkExt, StreamExt};
use neura_swarm::local_model::{self, LoopbackClient};
use serde_json::{json, Value};
use std::{
    io::{BufRead, BufReader},
    net::SocketAddr,
    path::PathBuf,
    process::{Child, Command, ExitCode, Stdio},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};
use tokio_tungstenite::{
    tungstenite::{client::IntoClientRequest, Message},
    MaybeTlsStream, WebSocketStream,
};

const EXIT_USAGE: u8 = 64;
const EXIT_MODEL_UNAVAILABLE: u8 = 2;
const EXIT_FAILED: u8 = 1;
const MAX_RUNS: u32 = 20;
const READY_TIMEOUT: Duration = Duration::from_secs(5);
const RUN_TIMEOUT: Duration = Duration::from_secs(90);
const MEMORY_SAMPLE: Duration = Duration::from_millis(200);
const SCHEMA_VERSION: u32 = 1;

const CONSENT: &str = "\
neura_engine_evidence measures the pinned local model (qwen3:4b-instruct) in
your own Ollama. It loads that model several times, sending only Neura's fixed
synthetic prompts. It never downloads a model, starts Ollama, or records prompt
or model text. Re-run with --confirm-local-model to proceed.";

#[derive(Debug, PartialEq, Eq)]
struct Options {
    runs: u32,
    out: Option<PathBuf>,
    sidecar: Option<PathBuf>,
}

fn parse(arguments: &[String]) -> Result<Options, String> {
    let mut options = Options {
        runs: 3,
        out: None,
        sidecar: None,
    };
    let mut confirmed = false;
    let mut iter = arguments.iter();
    while let Some(argument) = iter.next() {
        match argument.as_str() {
            "--confirm-local-model" => confirmed = true,
            "--runs" => {
                options.runs = iter
                    .next()
                    .and_then(|value| value.parse().ok())
                    .filter(|runs| (1..=MAX_RUNS).contains(runs))
                    .ok_or(format!("--runs takes a number from 1 to {MAX_RUNS}"))?;
            }
            "--out" => options.out = Some(iter.next().ok_or("--out takes a path")?.into()),
            "--sidecar" => {
                options.sidecar = Some(iter.next().ok_or("--sidecar takes a path")?.into());
            }
            _ => return Err("unknown argument".into()),
        }
    }
    if !confirmed {
        return Err(CONSENT.into());
    }
    Ok(options)
}

/// Available and total physical memory in bytes.
#[cfg(windows)]
fn memory() -> Option<(u64, u64)> {
    use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};
    // SAFETY: MEMORYSTATUSEX is a plain output structure initialized with its size.
    let mut status: MEMORYSTATUSEX = unsafe { std::mem::zeroed() };
    status.dwLength = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
    (unsafe { GlobalMemoryStatusEx(&mut status) } != 0)
        .then_some((status.ullAvailPhys, status.ullTotalPhys))
}
#[cfg(not(windows))]
fn memory() -> Option<(u64, u64)> {
    let info = std::fs::read_to_string("/proc/meminfo").ok()?;
    let field = |name: &str| -> Option<u64> {
        info.lines()
            .find(|line| line.starts_with(name))?
            .split_whitespace()
            .nth(1)?
            .parse::<u64>()
            .ok()
            .map(|kib| kib * 1024)
    };
    Some((field("MemAvailable:")?, field("MemTotal:")?))
}

/// Whether the machine is on mains power and its battery percentage.
#[cfg(windows)]
fn power() -> Value {
    use windows_sys::Win32::System::Power::{GetSystemPowerStatus, SYSTEM_POWER_STATUS};
    // SAFETY: SYSTEM_POWER_STATUS is a plain output structure.
    let mut status: SYSTEM_POWER_STATUS = unsafe { std::mem::zeroed() };
    if unsafe { GetSystemPowerStatus(&mut status) } == 0 {
        return Value::Null;
    }
    json!({
        "on_ac": match status.ACLineStatus { 0 => json!(false), 1 => json!(true), _ => Value::Null },
        "battery_percent": if status.BatteryLifePercent <= 100 {
            json!(status.BatteryLifePercent)
        } else {
            Value::Null
        },
    })
}
#[cfg(not(windows))]
fn power() -> Value {
    Value::Null
}

fn mib(bytes: u64) -> u64 {
    bytes / (1024 * 1024)
}

/// Samples available memory until stopped; reports the lowest value seen.
struct MemorySampler {
    stop: Arc<AtomicBool>,
    lowest: Arc<AtomicU64>,
    worker: Option<std::thread::JoinHandle<()>>,
}

impl MemorySampler {
    fn start() -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let lowest = Arc::new(AtomicU64::new(u64::MAX));
        let (flag, low) = (stop.clone(), lowest.clone());
        let worker = std::thread::spawn(move || {
            while !flag.load(Ordering::Relaxed) {
                if let Some((available, _)) = memory() {
                    low.fetch_min(available, Ordering::Relaxed);
                }
                std::thread::sleep(MEMORY_SAMPLE);
            }
        });
        Self {
            stop,
            lowest,
            worker: Some(worker),
        }
    }

    fn finish(mut self) -> Option<u64> {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
        Some(self.lowest.load(Ordering::Relaxed)).filter(|low| *low != u64::MAX)
    }
}

impl Drop for MemorySampler {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

fn fresh_token() -> Result<String, String> {
    let mut bytes = [0u8; 32];
    getrandom::getrandom(&mut bytes).map_err(|_| "no OS randomness")?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

fn default_sidecar() -> Option<PathBuf> {
    let name = if cfg!(windows) {
        "neura_api.exe"
    } else {
        "neura_api"
    };
    Some(std::env::current_exe().ok()?.parent()?.join(name))
}

/// Where and how to reach an authenticated sidecar.
struct Endpoint {
    address: SocketAddr,
    token: String,
}

impl Endpoint {
    async fn connect(&self) -> Result<Socket, String> {
        let mut request = format!("ws://{}/", self.address)
            .into_client_request()
            .map_err(|_| "bad sidecar address")?;
        request.headers_mut().insert(
            "Authorization",
            format!("Bearer {}", self.token)
                .parse()
                .map_err(|_| "bad credential")?,
        );
        let (socket, _) = tokio_tungstenite::connect_async(request)
            .await
            .map_err(|_| "could not connect to the sidecar")?;
        Ok(socket)
    }
}

/// The sidecar, launched with a restricted environment and the local adapter.
struct Sidecar {
    child: Child,
    endpoint: Endpoint,
}

impl Sidecar {
    fn launch(executable: &PathBuf) -> Result<Self, String> {
        let token = fresh_token()?;
        let mut command = Command::new(executable);
        command
            .env_clear()
            .env("NEURA_API_ADDR", "127.0.0.1:0")
            .env("NEURA_API_LAUNCHER_READY", "1")
            .env("NEURA_API_SESSION_TOKEN", &token)
            .env("NEURA_API_MODEL_ADAPTER", "ollama-local")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        if let Some(root) = std::env::var_os("SystemRoot") {
            command.env("SystemRoot", root);
        }
        let mut child = command
            .spawn()
            .map_err(|_| "could not start the sidecar; build neura_api first")?;
        let stdout = child.stdout.take().ok_or("no sidecar stdout")?;
        let (sender, receiver) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let mut line = String::new();
            let _ = BufReader::new(stdout).take_line(&mut line);
            let _ = sender.send(line);
        });
        let line = match receiver.recv_timeout(READY_TIMEOUT) {
            Ok(line) => line,
            Err(_) => {
                let _ = child.kill();
                return Err("the sidecar did not report readiness".into());
            }
        };
        let address = line
            .trim()
            .strip_prefix("NEURA_IPC_READY ")
            .and_then(|address| address.parse::<SocketAddr>().ok())
            .filter(|address| address.ip().is_loopback());
        let Some(address) = address else {
            let _ = child.kill();
            return Err("malformed sidecar readiness".into());
        };
        Ok(Self {
            child,
            endpoint: Endpoint { address, token },
        })
    }

    async fn revoke(&self) {
        if let Ok(client) = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_millis(500))
            .build()
        {
            let _ = client
                .post(format!("http://{}/session/revoke", self.endpoint.address))
                .bearer_auth(&self.endpoint.token)
                .send()
                .await;
        }
    }
}

impl Drop for Sidecar {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

trait TakeLine {
    fn take_line(self, line: &mut String) -> std::io::Result<usize>;
}

impl<R: std::io::Read> TakeLine for BufReader<R> {
    fn take_line(self, line: &mut String) -> std::io::Result<usize> {
        // Readiness is one short line; never buffer more than 128 bytes.
        std::io::Read::take(self, 128).read_line(line)
    }
}

type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

async fn send(socket: &mut Socket, kind: &str, data: Value) -> Result<(), String> {
    socket
        .send(Message::Text(
            json!({"v":1,"kind":kind,"data":data}).to_string(),
        ))
        .await
        .map_err(|_| "sidecar connection closed".into())
}

async fn receive(socket: &mut Socket) -> Result<Option<Value>, String> {
    loop {
        match tokio::time::timeout(RUN_TIMEOUT, socket.next()).await {
            Err(_) => return Err("timed out waiting for the sidecar".into()),
            Ok(None | Some(Err(_)) | Some(Ok(Message::Close(_)))) => return Ok(None),
            Ok(Some(Ok(Message::Text(text)))) => {
                return serde_json::from_str(&text)
                    .map(Some)
                    .map_err(|_| "malformed sidecar frame".into())
            }
            Ok(Some(Ok(_))) => {}
        }
    }
}

async fn request(socket: &mut Socket, kind: &str, expected: &str) -> Result<Value, String> {
    send(socket, kind, json!({})).await?;
    let reply = receive(socket)
        .await?
        .ok_or("sidecar closed the connection")?;
    if reply["kind"] != expected {
        return Err(format!("expected {expected} from the sidecar"));
    }
    Ok(reply["data"].clone())
}

/// One measured fixture run. Holds counts and timings only, never text.
async fn measure_run(socket: &mut Socket, fixture: &'static str) -> Result<Value, String> {
    let baseline = memory().map(|(available, _)| available);
    let sampler = MemorySampler::start();
    let started = Instant::now();
    send(socket, "synthetic_input", json!({"fixture":fixture})).await?;
    let (mut ttft, mut frames, mut bytes) = (None, 0u32, 0usize);
    let outcome = loop {
        let Some(frame) = receive(socket).await? else {
            break "closed".to_string();
        };
        match frame["kind"].as_str() {
            Some("speak_delta") => {
                ttft.get_or_insert_with(|| started.elapsed());
                frames += 1;
                bytes += frame["data"]["delta"].as_str().map_or(0, str::len);
            }
            Some("speak") => break "completed".to_string(),
            Some("error") => {
                break frame["data"]["code"]
                    .as_str()
                    .or(frame["data"]["message"].as_str())
                    .unwrap_or("error")
                    .to_string()
            }
            _ => return Err("unexpected sidecar frame".into()),
        }
    };
    let total = started.elapsed();
    let lowest = sampler.finish();
    let sidecar = request(socket, "diagnostics_request", "diagnostics")
        .await
        .map(|data| data["last_run"].clone())
        .unwrap_or(Value::Null);
    Ok(json!({
        "fixture": fixture,
        "outcome": outcome,
        "client_ttft_ms": ttft.map(|d| d.as_millis() as u64),
        "client_total_ms": total.as_millis() as u64,
        "delta_frames": frames,
        "output_bytes": bytes,
        "sidecar_ttft_ms": sidecar["ttft_ms"],
        "sidecar_total_ms": sidecar["total_ms"],
        "peak_memory_delta_mib": match (baseline, lowest) {
            (Some(base), Some(low)) => json!(mib(base.saturating_sub(low))),
            _ => Value::Null,
        },
        "power": power(),
    }))
}

/// Cancel a streaming run at its first delta and time the teardown, then time
/// how long until the adapter accepts new work again.
async fn measure_cancel(sidecar: &Endpoint) -> Result<Value, String> {
    let mut socket = sidecar.connect().await?;
    send(&mut socket, "synthetic_input", json!({"fixture":"stream"})).await?;
    loop {
        match receive(&mut socket).await? {
            Some(frame) if frame["kind"] == "speak_delta" => break,
            Some(frame) if frame["kind"] == "error" => {
                return Ok(json!({"outcome":"not_started"}));
            }
            Some(_) => {}
            None => return Err("sidecar closed before streaming".into()),
        }
    }
    let cancelled = Instant::now();
    send(&mut socket, "cancel", json!({})).await?;
    while receive(&mut socket).await?.is_some() {}
    let close_ms = cancelled.elapsed().as_millis() as u64;

    let mut socket = sidecar.connect().await?;
    let last = request(&mut socket, "diagnostics_request", "diagnostics").await?;
    let accept_ms = loop {
        send(&mut socket, "synthetic_input", json!({"fixture":"hello"})).await?;
        let frame = receive(&mut socket).await?.ok_or("sidecar closed")?;
        if frame["kind"] == "error" && frame["data"]["message"] == "local model busy" {
            if cancelled.elapsed() > RUN_TIMEOUT {
                return Err("the adapter stayed busy after cancel".into());
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
            continue;
        }
        break cancelled.elapsed().as_millis() as u64;
    };
    // End the follow-up run immediately; it only proves the permit was released.
    let _ = send(&mut socket, "cancel", json!({})).await;
    Ok(json!({
        "outcome": last["last_run"]["outcome"],
        "cancel_to_close_ms": close_ms,
        "cancel_to_next_accept_ms": accept_ms,
    }))
}

async fn model_footprint() -> Value {
    let Ok(client) = LoopbackClient::new(local_model::ENDPOINT, Duration::from_secs(3)) else {
        return Value::Null;
    };
    let Ok(response) = client.get("/api/tags").send().await else {
        return Value::Null;
    };
    let Ok(tags) = local_model::bounded_json(response, 1 << 20).await else {
        return Value::Null;
    };
    tags["models"]
        .as_array()
        .and_then(|models| {
            models
                .iter()
                .find(|model| model["name"] == local_model::MODEL)
        })
        .map(|model| json!({"size_bytes": model["size"], "digest": model["digest"]}))
        .unwrap_or(Value::Null)
}

fn summarize(runs: &[Value], fixture: &str, field: &str) -> Value {
    let mut values: Vec<u64> = runs
        .iter()
        .filter(|run| run["fixture"] == fixture && run["outcome"] == "completed")
        .filter_map(|run| run[field].as_u64())
        .collect();
    if values.is_empty() {
        return Value::Null;
    }
    values.sort_unstable();
    json!({
        "min": values[0],
        "median": values[values.len() / 2],
        "max": values[values.len() - 1],
        "count": values.len(),
    })
}

async fn collect(options: &Options) -> Result<(Value, u8), String> {
    let executable = options
        .sidecar
        .clone()
        .or_else(default_sidecar)
        .ok_or("cannot locate neura_api")?;
    let (available, total) = memory().unzip();
    let mut report = json!({
        "schema_version": SCHEMA_VERSION,
        "tool_version": env!("CARGO_PKG_VERSION"),
        "generated_at_unix_ms": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64,
        "host": {
            "os": std::env::consts::OS,
            "arch": std::env::consts::ARCH,
            "logical_cpus": std::thread::available_parallelism().map_or(0, |n| n.get()),
            "total_memory_mib": total.map(mib),
            "available_memory_mib": available.map(mib),
            "power": power(),
        },
        "model": {
            "tag": local_model::MODEL,
            "family": local_model::FAMILY,
            "parameter_size": local_model::PARAMETER_SIZE,
            "quantization": local_model::QUANTIZATION,
            "installed": model_footprint().await,
        },
    });
    let sidecar = Sidecar::launch(&executable)?;
    let mut socket = sidecar.endpoint.connect().await?;
    let hello = request(&mut socket, "hello", "hello").await?;
    if hello["model_adapter"] != "ollama-local" {
        return Err("the sidecar did not start the local adapter".into());
    }
    let diagnostics = request(&mut socket, "diagnostics_request", "diagnostics").await?;
    report["model_mode"] = diagnostics["model_mode"].clone();
    if diagnostics["model_mode"] != "local" {
        report["unavailable_code"] = diagnostics["checks"]
            .as_array()
            .and_then(|checks| checks.iter().find(|c| c["name"] == "Model adapter"))
            .map_or(Value::Null, |check| check["code"].clone());
        sidecar.revoke().await;
        return Ok((report, EXIT_MODEL_UNAVAILABLE));
    }
    let mut runs = Vec::new();
    for fixture in ["hello", "stream"] {
        for _ in 0..options.runs {
            runs.push(measure_run(&mut socket, fixture).await?);
        }
    }
    drop(socket);
    report["cancellation"] = measure_cancel(&sidecar.endpoint).await?;
    report["summary"] = json!({
        "hello": {
            "client_ttft_ms": summarize(&runs, "hello", "client_ttft_ms"),
            "client_total_ms": summarize(&runs, "hello", "client_total_ms"),
        },
        "stream": {
            "client_ttft_ms": summarize(&runs, "stream", "client_ttft_ms"),
            "client_total_ms": summarize(&runs, "stream", "client_total_ms"),
            "peak_memory_delta_mib": summarize(&runs, "stream", "peak_memory_delta_mib"),
        },
    });
    report["runs"] = Value::Array(runs);
    sidecar.revoke().await;
    Ok((report, 0))
}

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let options = match parse(&arguments) {
        Ok(options) => options,
        Err(message) => {
            eprintln!("{message}");
            return ExitCode::from(EXIT_USAGE);
        }
    };
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(_) => return ExitCode::from(EXIT_FAILED),
    };
    let (report, code) = match runtime.block_on(collect(&options)) {
        Ok(result) => result,
        Err(message) => {
            eprintln!("evidence collection failed: {message}");
            return ExitCode::from(EXIT_FAILED);
        }
    };
    let text = serde_json::to_string_pretty(&report).unwrap_or_default();
    match &options.out {
        Some(path) => {
            if std::fs::write(path, text + "\n").is_err() {
                eprintln!("could not write the report");
                return ExitCode::from(EXIT_FAILED);
            }
        }
        None => println!("{text}"),
    }
    if code == EXIT_MODEL_UNAVAILABLE {
        eprintln!("The pinned local model is not available; see model_mode and unavailable_code.");
    }
    ExitCode::from(code)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    #[test]
    fn consent_is_required_and_arguments_are_bounded() {
        assert_eq!(parse(&args(&[])).unwrap_err(), CONSENT);
        assert_eq!(parse(&args(&["--runs", "2"])).unwrap_err(), CONSENT);
        assert_eq!(
            parse(&args(&["--confirm-local-model"])).unwrap(),
            Options {
                runs: 3,
                out: None,
                sidecar: None
            }
        );
        let parsed = parse(&args(&[
            "--confirm-local-model",
            "--runs",
            "5",
            "--out",
            "e.json",
        ]))
        .unwrap();
        assert_eq!(parsed.runs, 5);
        assert_eq!(parsed.out, Some(PathBuf::from("e.json")));
        for bad in [
            &["--confirm-local-model", "--runs", "0"][..],
            &["--confirm-local-model", "--runs", "21"],
            &["--confirm-local-model", "--runs"],
            &["--confirm-local-model", "--prompt", "hi"],
            &["--confirm-local-model", "--out"],
        ] {
            assert!(parse(&args(bad)).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn summaries_use_only_completed_runs_of_one_fixture() {
        let runs = vec![
            json!({"fixture":"hello","outcome":"completed","client_total_ms":300}),
            json!({"fixture":"hello","outcome":"completed","client_total_ms":100}),
            json!({"fixture":"hello","outcome":"completed","client_total_ms":200}),
            json!({"fixture":"hello","outcome":"exhausted","client_total_ms":9000}),
            json!({"fixture":"stream","outcome":"completed","client_total_ms":5000}),
        ];
        assert_eq!(
            summarize(&runs, "hello", "client_total_ms"),
            json!({"min":100,"median":200,"max":300,"count":3})
        );
        assert_eq!(summarize(&runs, "hello", "client_ttft_ms"), Value::Null);
    }

    #[test]
    fn memory_and_sampler_report_plausible_values() {
        if let Some((available, total)) = memory() {
            assert!(available <= total && total > 0);
        }
        let sampler = MemorySampler::start();
        std::thread::sleep(MEMORY_SAMPLE * 2);
        if memory().is_some() {
            assert!(sampler.finish().is_some());
        }
    }

    /// Loopback stand-in for a local-mode sidecar. `hello` completes at once;
    /// `stream` keeps streaming until the client cancels. After a cancel the
    /// next request is refused as busy once, like the adapter-wide permit.
    async fn mock_sidecar() -> (Endpoint, Arc<AtomicU64>) {
        use tokio_tungstenite::tungstenite::Message as M;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let busy_after_cancel = Arc::new(AtomicBool::new(false));
        let chats = Arc::new(AtomicU64::new(0));
        let chat_count = chats.clone();
        tokio::spawn(async move {
            loop {
                let (stream, _) = listener.accept().await.unwrap();
                let busy = busy_after_cancel.clone();
                let chats = chat_count.clone();
                tokio::spawn(async move {
                    let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
                    let mut last = Value::Null;
                    while let Some(Ok(M::Text(text))) = ws.next().await {
                        let request: Value = serde_json::from_str(&text).unwrap();
                        let frame = |kind: &str, data: Value| {
                            M::Text(json!({"v":1,"kind":kind,"data":data}).to_string())
                        };
                        match request["kind"].as_str().unwrap() {
                            "diagnostics_request" => {
                                let data = json!({"model_mode":"local","last_run":last});
                                ws.send(frame("diagnostics", data)).await.unwrap();
                            }
                            "cancel" => {
                                busy.store(true, Ordering::SeqCst);
                                return;
                            }
                            "synthetic_input" if busy.swap(false, Ordering::SeqCst) => {
                                let data = json!({"message":"local model busy"});
                                ws.send(frame("error", data)).await.unwrap();
                            }
                            "synthetic_input" => {
                                chats.fetch_add(1, Ordering::SeqCst);
                                let fixture = request["data"]["fixture"].clone();
                                if fixture == "stream" {
                                    // Stream until the client cancels or disconnects.
                                    loop {
                                        let delta = frame("speak_delta", json!({"delta":"wave "}));
                                        if ws.send(delta).await.is_err() {
                                            return;
                                        }
                                        tokio::select! {
                                            next = ws.next() => {
                                                if let Some(Ok(M::Text(t))) = next {
                                                    if t.contains("\"cancel\"") {
                                                        busy.store(true, Ordering::SeqCst);
                                                    }
                                                }
                                                return;
                                            }
                                            _ = tokio::time::sleep(Duration::from_millis(20)) => {}
                                        }
                                    }
                                }
                                for delta in ["Link ", "works."] {
                                    let data = json!({"delta":delta});
                                    ws.send(frame("speak_delta", data)).await.unwrap();
                                }
                                let done = json!({"text":"Link works."});
                                ws.send(frame("speak", done)).await.unwrap();
                                last = json!({"fixture":fixture,"outcome":"completed",
                                    "ttft_ms":5,"total_ms":9,"output_bytes":11});
                            }
                            _ => {}
                        }
                    }
                });
            }
        });
        let endpoint = Endpoint {
            address,
            token: "ab".repeat(32),
        };
        (endpoint, chats)
    }

    #[tokio::test]
    async fn a_measured_run_records_counts_and_timings_but_no_text() {
        let (endpoint, _) = mock_sidecar().await;
        let mut socket = endpoint.connect().await.unwrap();
        let run = measure_run(&mut socket, "hello").await.unwrap();
        assert_eq!(run["fixture"], "hello");
        assert_eq!(run["outcome"], "completed");
        assert_eq!(run["delta_frames"], 2);
        assert_eq!(run["output_bytes"], "Link works.".len());
        assert!(run["client_ttft_ms"].is_u64() && run["client_total_ms"].is_u64());
        assert_eq!(run["sidecar_ttft_ms"], 5);
        assert_eq!(run["sidecar_total_ms"], 9);
        assert!(
            !run.to_string().contains("Link"),
            "no model text in the report"
        );
    }

    #[tokio::test]
    async fn cancellation_is_timed_and_waits_for_the_permit() {
        let (endpoint, chats) = mock_sidecar().await;
        let cancel = measure_cancel(&endpoint).await.unwrap();
        assert!(cancel["cancel_to_close_ms"].is_u64());
        let close = cancel["cancel_to_close_ms"].as_u64().unwrap();
        let accept = cancel["cancel_to_next_accept_ms"].as_u64().unwrap();
        // The first follow-up was refused as busy and retried.
        assert!(accept >= close);
        // One streamed run plus one accepted follow-up; the busy refusal ran nothing.
        assert_eq!(chats.load(Ordering::SeqCst), 2);
        assert!(!cancel.to_string().contains("wave"));
    }
}
