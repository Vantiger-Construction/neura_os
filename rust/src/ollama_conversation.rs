//! Opt-in Windows chat adapter. The operator owns the separately installed
//! Ollama daemon; Neura owns only its cancellable request, never that process.
use crate::ollama_latency::{RequestTiming, TIMING_FIELDS};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    sync::{Arc, Mutex, OnceLock},
    thread::JoinHandle,
    time::{Duration, Instant},
};
use tokio::sync::watch;
use zeroize::Zeroizing;

use crate::local_model::{
    memory_admitted, memory_snapshot, stream_chat_reply, verify_pin, ModelPin, StreamLimits,
    ENDPOINT, LARGE_PIN, LOCAL_MODEL, STANDARD_PIN,
};
/// System (8 KiB) + history (4 KB, plus a tool round) + tools (3 KiB) + JSON.
const MAX_REQUEST: usize = 24_576;
const MAX_REPLY: usize = 8_192;
/// Context window. 4,096 tokens holds the charter (~1.6k tokens), several
/// recent exchanges and a full reply; its KV cache costs ~0.6 GB on the 4B
/// model, versus ~1.1 GB more for 8,192, which an 8 GB laptop cannot spare.
const NUM_CTX: u32 = 4_096;
/// Longest reply in tokens (about 350 words).
const NUM_PREDICT: u32 = 512;
/// Shortest reply cap the app may request (a spoken reply asks for fewer
/// tokens than a typed one, because on a laptop CPU each token costs ~0.5 s).
const MIN_MAX_TOKENS: u32 = 32;
/// Recent turns and their combined UTF-8 bytes retained per request; matches
/// the Dart `NeuraOfflineBudget.standard` cap.
const MAX_TURNS: usize = 16;
const MAX_HISTORY_BYTES: usize = 4_000;
/// Charter, room and audience framing plus up to 1,500 bytes of approved notes.
const MAX_SYSTEM_BYTES: usize = 8_192;
/// A short per-turn note (the tentative mood read). It is sent as a system
/// message after the newest turn instead of inside the charter, so the charter
/// and earlier turns stay byte-identical between turns and Ollama reuses their
/// cached prompt evaluation. On a 4-core laptop CPU that cache saves minutes.
const MAX_CUE_BYTES: usize = 512;
/// Whole-reply deadline. A 512-token reply on a 4-core laptop CPU takes about
/// 100 s on the 4B model and about 200 s on the 8B, streaming throughout.
const REPLY_DEADLINE: Duration = Duration::from_secs(300);
/// Longest silence from the daemon, including a cold model load, before the
/// request fails as stalled.
const STREAM_IDLE: Duration = Duration::from_secs(120);
/// The larger model needs ~6 GB for weights plus its 4,096-token cache.
const LARGE_MIN_TOTAL_MIB: u64 = 14_336;
const LARGE_MIN_AVAILABLE_MIB: u64 = 6_656;
/// RAM alone does not make the larger model usable. Measured on a 4-core
/// laptop CPU (AMD A12-9800B, 15 GB): the 4B model reads prompts at ~5 tok/s
/// and writes ~1.5-2 tok/s, and the 8B is about half that, so a reply would
/// take several minutes. Require enough cores to keep it conversational.
const LARGE_MIN_PHYSICAL_CORES: usize = 6;

/// Whether this host can hold the larger model right now. A model already
/// resident from the previous turn does not count against available RAM.
fn large_admitted(resident_large: bool) -> bool {
    large_cores_admitted(physical_cores())
        && memory_snapshot().is_some_and(|(total, available)| {
            total >= LARGE_MIN_TOTAL_MIB
                && available <= total
                && (resident_large || available >= LARGE_MIN_AVAILABLE_MIB)
        })
}

/// Unknown core counts are treated as too few.
fn large_cores_admitted(cores: Option<usize>) -> bool {
    cores.is_some_and(|cores| cores >= LARGE_MIN_PHYSICAL_CORES)
}
const READINESS_FIELDS: usize = 7;
/// Streamed NDJSON carries per-token framing, so the body budget is larger
/// than the reply budget; the assistant text itself stays bounded by MAX_REPLY.
const STREAM_LIMITS: StreamLimits = StreamLimits {
    max_line: 4_096,
    max_output: MAX_REPLY,
    max_response: 262_144,
};
/// Ollama keeps the model loaded this long after a reply, so follow-up turns
/// in a conversation skip the multi-second cold load. Ollama unloads it after
/// this idle window; Neura never pins it indefinitely.
const KEEP_ALIVE: &str = "5m";
/// Trust that the model is still resident for slightly less than KEEP_ALIVE.
/// A resident model already occupies RAM, so the available-memory floor would
/// otherwise reject the very follow-up turn residency is meant to speed up.
const RESIDENCY_TRUST: Duration = Duration::from_secs(240);
const MIN_TOTAL_MIB: u64 = 7_168;

/// Physical cores minus one (keeps a core for the UI and speech), within 2..=8.
fn inference_threads() -> usize {
    static THREADS: OnceLock<usize> = OnceLock::new();
    *THREADS.get_or_init(|| {
        physical_cores()
            .map_or(2, |cores| cores.saturating_sub(1))
            .clamp(2, 8)
    })
}

#[cfg(windows)]
fn physical_cores() -> Option<usize> {
    use windows_sys::Win32::System::SystemInformation::{
        GetLogicalProcessorInformation, RelationProcessorCore, SYSTEM_LOGICAL_PROCESSOR_INFORMATION,
    };
    let entry = std::mem::size_of::<SYSTEM_LOGICAL_PROCESSOR_INFORMATION>();
    let mut bytes = 0u32;
    // SAFETY: a null buffer with zero length only queries the required size.
    unsafe { GetLogicalProcessorInformation(std::ptr::null_mut(), &mut bytes) };
    if bytes == 0 {
        return None;
    }
    let mut info: Vec<SYSTEM_LOGICAL_PROCESSOR_INFORMATION> = (0..(bytes as usize).div_ceil(entry))
        .map(|_| Default::default())
        .collect();
    let mut length = (info.len() * entry) as u32;
    // SAFETY: `info` is a live, aligned buffer of `length` bytes.
    if unsafe { GetLogicalProcessorInformation(info.as_mut_ptr(), &mut length) } == 0 {
        return None;
    }
    let cores = info
        .iter()
        .take(length as usize / entry)
        .filter(|item| item.Relationship == RelationProcessorCore)
        .count();
    (cores > 0).then_some(cores)
}

#[cfg(not(windows))]
fn physical_cores() -> Option<usize> {
    std::thread::available_parallelism()
        .ok()
        .map(|logical| (logical.get() / 2).max(1))
}

/// Most tool definitions accepted per request, and their combined JSON size.
const MAX_TOOLS: usize = 6;
const MAX_TOOLS_BYTES: usize = 3_072;
const MAX_TOOL_DESCRIPTION: usize = 600;

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ToolCall {
    name: String,
    arguments: serde_json::Map<String, Value>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Turn {
    role: String,
    content: String,
    /// Calls an earlier assistant turn requested (tool rounds only).
    #[serde(default)]
    tool_calls: Vec<ToolCall>,
    /// The tool a `tool` turn answers.
    #[serde(default)]
    tool_name: Option<String>,
}
impl Turn {
    fn budget_bytes(&self) -> usize {
        self.content.len()
            + self
                .tool_calls
                .iter()
                .map(|c| c.name.len() + Value::Object(c.arguments.clone()).to_string().len())
                .sum::<usize>()
    }
    fn to_ollama(&self) -> Value {
        match self.role.as_str() {
            "tool" => json!({"role": "tool", "content": self.content,
                "tool_name": self.tool_name}),
            "assistant" if !self.tool_calls.is_empty() => json!({
                "role": "assistant", "content": self.content,
                "tool_calls": self.tool_calls.iter().map(|c| json!({
                    "function": {"name": c.name, "arguments": c.arguments}
                })).collect::<Vec<_>>(),
            }),
            role => json!({"role": role, "content": self.content}),
        }
    }
}
/// A tool the app may run after its own policy check and user confirmation.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Tool {
    name: String,
    description: String,
    parameters: Value,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    system: String,
    #[serde(default)]
    messages: Vec<Turn>,
    #[serde(default)]
    tools: Vec<Tool>,
    #[serde(default)]
    cue: String,
    /// Reply cap below NUM_PREDICT, for replies that will be spoken.
    #[serde(default)]
    max_tokens: Option<u32>,
    /// Load the model and pre-evaluate the charter and tools only: no turns,
    /// one output token. The next reply with the same charter and tools then
    /// skips both the cold load and the charter's prompt evaluation.
    #[serde(default)]
    warm: bool,
}

fn valid_tools(tools: &[Tool]) -> bool {
    let bytes: usize = tools
        .iter()
        .map(|t| t.name.len() + t.description.len() + t.parameters.to_string().len())
        .sum();
    tools.len() <= MAX_TOOLS
        && bytes <= MAX_TOOLS_BYTES
        && tools.iter().all(|t| {
            crate::local_model::valid_tool_name(&t.name)
                && t.description.len() <= MAX_TOOL_DESCRIPTION
                && t.parameters.is_object()
        })
}

fn valid_turn(turn: &Turn, tools: &[Tool]) -> bool {
    let advertised = |name: &str| tools.iter().any(|t| t.name == name);
    match turn.role.as_str() {
        "user" => turn.tool_calls.is_empty() && turn.tool_name.is_none(),
        "assistant" => {
            turn.tool_name.is_none()
                && turn.tool_calls.len() <= crate::local_model::MAX_TOOL_CALLS
                && turn.tool_calls.iter().all(|c| advertised(&c.name))
        }
        "tool" => turn.tool_calls.is_empty() && turn.tool_name.as_deref().is_some_and(advertised),
        _ => false,
    }
}

fn prepare(raw: &[u8]) -> Result<Value, ()> {
    let request: Request = serde_json::from_slice(raw).map_err(|_| ())?;
    if request.system.is_empty()
        || request.system.len() > MAX_SYSTEM_BYTES
        || request.cue.len() > MAX_CUE_BYTES
        || request
            .max_tokens
            .is_some_and(|n| !(MIN_MAX_TOKENS..=NUM_PREDICT).contains(&n))
        || !valid_tools(&request.tools)
    {
        return Err(());
    }
    if request.warm {
        // A warm-up carries no conversation text at all.
        if !request.messages.is_empty() || !request.cue.is_empty() || request.max_tokens.is_some() {
            return Err(());
        }
        let messages = vec![json!({"role":"system", "content": request.system})];
        return Ok(payload_for(messages, 1, &request.tools));
    }
    if request.messages.is_empty()
        || request.messages.len() > 64
        || !matches!(
            request.messages.last().map(|t| t.role.as_str()),
            Some("user" | "tool")
        )
        || request
            .messages
            .iter()
            .any(|t| !valid_turn(t, &request.tools))
    {
        return Err(());
    }
    // Retain whole recent turns, never truncate the charter or newest message.
    // The byte budget keeps charter + history + reply inside NUM_CTX tokens.
    let mut retained = Vec::new();
    let mut bytes = 0;
    for turn in request.messages.into_iter().rev().take(MAX_TURNS) {
        let size = turn.budget_bytes();
        if bytes + size > MAX_HISTORY_BYTES {
            if retained.is_empty() {
                return Err(());
            }
            break;
        }
        bytes += size;
        retained.push(turn);
    }
    retained.reverse();
    while retained.first().is_some_and(|t| t.role != "user") {
        retained.remove(0);
    }
    // A tool round whose originating user turn no longer fits is unusable.
    if retained.is_empty() {
        return Err(());
    }
    let mut messages = vec![json!({"role":"system", "content": request.system})];
    messages.extend(retained.iter().map(Turn::to_ollama));
    if !request.cue.trim().is_empty() {
        messages.push(json!({"role":"system", "content": request.cue}));
    }
    let num_predict = request.max_tokens.unwrap_or(NUM_PREDICT);
    Ok(payload_for(messages, num_predict, &request.tools))
}

/// The Ollama request body. Warm-ups and replies share every option except
/// `num_predict`, so a warm-up primes exactly the prefix the reply will reuse.
fn payload_for(messages: Vec<Value>, num_predict: u32, tools: &[Tool]) -> Value {
    let mut payload = json!({"model": LOCAL_MODEL, "messages": messages, "stream": true,
        "think": false, "keep_alive": KEEP_ALIVE, "options": {"num_ctx":NUM_CTX,
        "num_predict":num_predict, "num_thread":inference_threads(),"temperature":0.6}});
    if !tools.is_empty() {
        payload["tools"] = tools
            .iter()
            .map(|t| {
                json!({"type": "function", "function": {
                    "name": t.name, "description": t.description, "parameters": t.parameters,
                }})
            })
            .collect();
    }
    payload
}

#[cfg(test)]
async fn inference(endpoint: &str, payload: Value) -> Result<String, ()> {
    timed_inference(
        endpoint,
        payload,
        &Mutex::new(RequestTiming::default()),
        |_| true,
        false,
    )
    .await
    .map(|(text, _)| text)
}

/// Picks the model: the larger pin when requested and verified, otherwise the
/// standard pin. Every candidate passes the same identity checks first.
async fn select_pin(
    client: &crate::local_model::LoopbackClient,
    try_large: bool,
) -> Result<&'static ModelPin, ()> {
    if try_large && verify_pin(client, &LARGE_PIN).await.is_ok() {
        return Ok(&LARGE_PIN);
    }
    verify_pin(client, &STANDARD_PIN).await.map_err(|_| ())?;
    Ok(&STANDARD_PIN)
}

/// Streams the reply, handing each text delta to `publish` so the UI and
/// speech can start before generation ends. `publish` returning false stops
/// the request (superseded, cancelled, backgrounded or blocked). Returns the
/// text and whether the larger model produced it.
async fn timed_inference(
    endpoint: &str,
    mut payload: Value,
    timing: &Mutex<RequestTiming>,
    publish: impl FnMut(&str) -> bool,
    try_large: bool,
) -> Result<(String, bool), ()> {
    let client =
        crate::local_model::LoopbackClient::streaming(endpoint, REPLY_DEADLINE, STREAM_IDLE)?;
    // Fail before submitting conversation text if this tag is a remote model
    // or has been replaced with a different family/size/quantization.
    let pin = select_pin(&client, try_large).await?;
    payload["model"] = json!(pin.local_tag);
    timing
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .preflight_done();
    let large = std::ptr::eq(pin, &LARGE_PIN);
    let tools = payload.get("tools").is_some();
    // Rejects remote models, unadvertised tool calls, error lines, oversize
    // output and a body that ends without the final `done` line.
    let reply = stream_chat_reply(&client, &payload, STREAM_LIMITS, publish, tools)
        .await
        .map_err(|_| ())?;
    // num_predict stops a long reply mid-word. Show and speak whole sentences.
    // Only whole sentences were released while streaming, so this never
    // contradicts what the app already showed.
    let text = if reply.length_capped {
        finish_at_sentence(&reply.text)
    } else {
        reply.text.as_str().to_owned()
    };
    if !tools {
        return Ok((text, large));
    }
    // With advertised tools the reply is a JSON envelope; the app re-checks
    // every call against its room policy and asks the user before running it.
    let envelope = json!({"text": text, "tool_calls": reply.tool_calls}).to_string();
    if envelope.len() > MAX_REPLY {
        return Err(());
    }
    Ok((envelope, large))
}

/// Shortens a reply that hit the token cap to its last complete sentence or
/// line. A sentence that only introduces what was cut ("Try these:") is
/// dropped too. With no complete sentence, it ends at a word with an ellipsis.
fn finish_at_sentence(text: &str) -> String {
    const ABBREVIATIONS: [&str; 8] = ["e.g", "i.e", "dr", "mr", "mrs", "ms", "st", "vs"];
    let chars: Vec<(usize, char)> = text.char_indices().collect();
    let is_closer = |c: char| {
        matches!(
            c,
            '"' | '\'' | '\u{201D}' | '\u{2019}' | ')' | ']' | '*' | '_'
        )
    };
    let mut ends = Vec::new();
    for (i, &(at, c)) in chars.iter().enumerate() {
        if c == '\n' {
            ends.push(at);
            continue;
        }
        if !matches!(c, '.' | '!' | '?' | '\u{2026}') {
            continue;
        }
        let mut j = i + 1;
        while j < chars.len() && (matches!(chars[j].1, '.' | '!' | '?') || is_closer(chars[j].1)) {
            j += 1;
        }
        // A boundary needs following whitespace; the cut tail is never one.
        if j >= chars.len() || !chars[j].1.is_whitespace() {
            continue;
        }
        let line_start = text[..at].rfind('\n').map_or(0, |n| n + 1);
        let word_start = text[..at]
            .rfind(|ch: char| ch.is_whitespace() || ch == '(')
            .map_or(0, |n| n + 1);
        let word = text[word_start..at].to_lowercase();
        let list_marker = c == '.'
            && !word.is_empty()
            && word.chars().all(|ch| ch.is_ascii_digit())
            && text[line_start..word_start].trim().is_empty();
        if list_marker || (c == '.' && ABBREVIATIONS.contains(&word.as_str())) {
            continue;
        }
        ends.push(chars.get(j).map_or(text.len(), |&(b, _)| b));
    }
    for &end in ends.iter().rev() {
        let kept = text[..end].trim_end();
        let bare = kept.trim_end_matches(['*', '_', '#', ' ']);
        // A bare list marker or a heading is not a finished thought.
        let marker_only = kept.rsplit('\n').next().is_some_and(|line| {
            let line = line.trim();
            line.starts_with('#')
                || line.trim_end_matches(['.', ')']).chars().all(|ch| {
                    ch.is_ascii_digit() || matches!(ch, '-' | '*' | '+' | '\u{2022}' | ' ')
                })
        });
        if !bare.is_empty() && !bare.ends_with(':') && !marker_only {
            return kept.to_owned();
        }
    }
    let cut = text.trim_end();
    let cut = cut
        .rfind(char::is_whitespace)
        .map_or(cut, |n| cut[..n].trim_end());
    format!(
        "{}\u{2026}",
        cut.trim_end_matches([',', ';', ':', '-', ' '])
    )
}

async fn cancellable_inference(
    endpoint: &str,
    payload: Value,
    timing: &Mutex<RequestTiming>,
    receiver: &mut watch::Receiver<bool>,
    publish: impl FnMut(&str) -> bool,
    try_large: bool,
) -> Result<(String, bool), ()> {
    tokio::select! { biased;
        _ = receiver.changed() => Err(()),
        result = tokio::time::timeout(REPLY_DEADLINE, timed_inference(endpoint, payload, timing, publish, try_large)) => result.map_err(|_| ())?,
    }
}

fn readiness_snapshot(
    model: crate::local_model::ModelReadiness,
    memory: Option<(u64, u64)>,
) -> [u64; READINESS_FIELDS] {
    let (total, available) = memory.unwrap_or_default();
    let admission = match memory {
        None => 0,
        Some((total, available))
            if crate::local_model::memory_values_admitted(total, available) =>
        {
            1
        }
        Some(_) => 2,
    };
    [
        1,
        model.daemon,
        model.version,
        model.model,
        admission,
        total,
        available,
    ]
}

async fn cancellable_readiness(
    endpoint: &str,
    receiver: &mut watch::Receiver<bool>,
) -> Result<[u64; READINESS_FIELDS], ()> {
    tokio::select! { biased;
        _ = receiver.changed() => Err(()),
        result = tokio::time::timeout(Duration::from_secs(10), async {
            let client = crate::local_model::LoopbackClient::new(endpoint, Duration::from_secs(3))?;
            let model = crate::local_model::inspect_pinned_model(&client).await;
            Ok(readiness_snapshot(model, crate::local_model::memory_snapshot()))
        }) => result.map_err(|_| ())?,
    }
}

enum Completion {
    /// Reply text and whether the larger model produced it.
    Reply(String, bool),
    Readiness([u64; READINESS_FIELDS]),
}

#[derive(Default)]
struct State {
    generation: i64,
    foreground: bool,
    blocked: bool,
    status: i32,
    reply: Option<Zeroizing<Vec<u8>>>,
    /// Text streamed so far for the current generation, for `neura_ollama_peek`.
    partial: Option<Zeroizing<Vec<u8>>>,
    readiness: Option<[u64; READINESS_FIELDS]>,
    timing: Option<(i64, Arc<Mutex<RequestTiming>>)>,
    /// Until when the model is presumed still loaded after a delivered reply.
    resident_until: Option<Instant>,
    /// Whether that resident model is the larger pin.
    resident_large: bool,
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
        state.partial = None;
        state.readiness = None;
        state.status = -2;
        if let Some(active) = &self.active {
            active.cancel.send_replace(true);
        }
    }
    fn begin(&mut self, payload: Value) -> i64 {
        let resident = self.resident_now();
        self.begin_checked(payload, || {
            memory_admitted() || (resident && total_memory_admitted())
        })
    }
    /// A recently delivered reply means Ollama is still holding the model, so
    /// the RAM it occupies must not count against the next turn's admission.
    /// The installed-RAM floor still applies.
    fn resident_now(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .resident_until
            .is_some_and(|until| Instant::now() < until)
    }
    fn begin_checked(&mut self, payload: Value, admit_memory: impl FnOnce() -> bool) -> i64 {
        self.begin_work(Some(payload), admit_memory)
    }
    fn begin_readiness(&mut self) -> i64 {
        // Metadata inspection never loads weights, even when memory is low.
        self.begin_work(None, || true)
    }
    fn begin_work(&mut self, payload: Option<Value>, admit_memory: impl FnOnce() -> bool) -> i64 {
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
        let timing = payload
            .as_ref()
            .map(|_| Arc::new(Mutex::new(RequestTiming::default())));
        let generation = {
            let mut state = self.state.lock().unwrap_or_else(|p| p.into_inner());
            state.status = 0;
            state.timing = timing
                .as_ref()
                .map(|value| (state.generation, value.clone()));
            state.generation
        };
        let (cancel, mut receiver) = watch::channel(false);
        let state = self.state.clone();
        let stream_state = self.state.clone();
        let worker = std::thread::Builder::new()
            .name("neura-ollama".into())
            .spawn(move || {
                // Append each delta for this generation only; a superseded,
                // cancelled, backgrounded or blocked request stops streaming.
                let publish = move |delta: &str| {
                    let mut state = stream_state.lock().unwrap_or_else(|p| p.into_inner());
                    if generation != state.generation || state.blocked || !state.foreground {
                        return false;
                    }
                    let partial = state
                        .partial
                        .get_or_insert_with(|| Zeroizing::new(Vec::new()));
                    if partial.len() + delta.len() > MAX_REPLY {
                        return false;
                    }
                    partial.extend_from_slice(delta.as_bytes());
                    true
                };
                // Prefer the larger model only when it fits now; keep using
                // whichever model is still resident to avoid loading both.
                let resident_large = {
                    let state = state.lock().unwrap_or_else(|p| p.into_inner());
                    state.resident_large
                        && state
                            .resident_until
                            .is_some_and(|until| Instant::now() < until)
                };
                let try_large = payload.is_some() && large_admitted(resident_large);
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    let runtime = tokio::runtime::Builder::new_current_thread()
                        .enable_all()
                        .build()
                        .map_err(|_| ())?;
                    tracing::subscriber::with_default(
                        tracing::subscriber::NoSubscriber::default(),
                        || {
                            runtime.block_on(async {
                                match payload {
                                    Some(payload) => cancellable_inference(
                                        ENDPOINT,
                                        payload,
                                        timing.as_ref().ok_or(())?,
                                        &mut receiver,
                                        publish,
                                        try_large,
                                    )
                                    .await
                                    .map(|(text, large)| Completion::Reply(text, large)),
                                    None => cancellable_readiness(ENDPOINT, &mut receiver)
                                        .await
                                        .map(Completion::Readiness),
                                }
                            })
                        },
                    )
                }));
                let mut state = state.lock().unwrap_or_else(|p| p.into_inner());
                if let Some(timing) = timing {
                    timing
                        .lock()
                        .unwrap_or_else(|p| p.into_inner())
                        .worker_done(matches!(&result, Ok(Ok(_))));
                }
                if generation != state.generation || state.blocked || !state.foreground {
                    return;
                }
                match result {
                    Ok(Ok(Completion::Reply(text, large))) => {
                        state.reply = Some(Zeroizing::new(text.into_bytes()));
                        state.status = 1;
                        state.resident_until = Some(Instant::now() + RESIDENCY_TRUST);
                        state.resident_large = large;
                    }
                    Ok(Ok(Completion::Readiness(snapshot))) => {
                        state.readiness = Some(snapshot);
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
fn total_memory_admitted() -> bool {
    memory_snapshot().is_some_and(|(total, _)| total >= MIN_TOTAL_MIB)
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

/// Explicit, argument-free metadata inspection. Shares the cancellable worker,
/// foreground ownership, busy rejection and latched safety block with chat.
#[no_mangle]
pub extern "C" fn neura_ollama_readiness_begin() -> i64 {
    session()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .begin_readiness()
}

/// # Safety
/// `buffer` must point to `capacity` aligned, writable u64 elements.
#[no_mangle]
pub unsafe extern "C" fn neura_ollama_readiness_poll(
    id: i64,
    buffer: *mut u64,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity < READINESS_FIELDS {
        return -1;
    }
    let session = session().lock().unwrap_or_else(|p| p.into_inner());
    let mut state = session.state.lock().unwrap_or_else(|p| p.into_inner());
    if id != state.generation || state.blocked || !state.foreground {
        return -2;
    }
    if state.status != 1 {
        return state.status;
    }
    let Some(snapshot) = state.readiness.take() else {
        return -1;
    };
    // SAFETY: the caller supplies a separate aligned output buffer of sufficient size.
    unsafe {
        std::ptr::copy_nonoverlapping(snapshot.as_ptr(), buffer, READINESS_FIELDS);
    }
    state.status = -2;
    READINESS_FIELDS as i32
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
/// Copy the text streamed so far for `id` without consuming it. Returns its
/// byte length (0 before the first token), or the request's negative status.
/// The text grows by appending whole UTF-8 deltas, so every copy is valid UTF-8
/// and a prefix of the next. The verified final reply still comes from poll.
/// # Safety
/// `buffer` must point to `capacity` writable bytes for this synchronous call.
#[no_mangle]
pub unsafe extern "C" fn neura_ollama_peek(id: i64, buffer: *mut u8, capacity: usize) -> i32 {
    let session = session().lock().unwrap_or_else(|p| p.into_inner());
    let state = session.state.lock().unwrap_or_else(|p| p.into_inner());
    if id != state.generation || state.blocked || !state.foreground {
        return -2;
    }
    if state.status < 0 {
        return state.status;
    }
    let Some(partial) = state.partial.as_ref() else {
        return 0;
    };
    if buffer.is_null() || capacity < partial.len() {
        return -1;
    }
    // SAFETY: caller provides a separate, sufficiently sized output buffer.
    unsafe {
        std::ptr::copy_nonoverlapping(partial.as_ptr(), buffer, partial.len());
    }
    partial.len() as i32
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
    {
        let mut state = session.state.lock().unwrap_or_else(|p| p.into_inner());
        state.blocked = true;
        state.resident_until = None;
    }
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
    {
        let mut state = session.state.lock().unwrap_or_else(|p| p.into_inner());
        state.blocked = true;
        state.resident_until = None;
    }
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
    /// Serializes tests that replace the process-wide native session.
    static GLOBAL_SESSION: Mutex<()> = Mutex::new(());
    #[test]
    fn fixes_model_and_resource_limits_and_preserves_system() {
        let payload = prepare(
            br#"{"system":"Neura charter","messages":[{"role":"user","content":"Hello"}]}"#,
        )
        .unwrap();
        assert_eq!(payload["model"], LOCAL_MODEL);
        assert_eq!(payload["messages"][0]["content"], "Neura charter");
        assert_eq!(payload["options"]["num_ctx"], 4096);
        assert_eq!(payload["options"]["num_predict"], 512);
        assert_eq!(payload["keep_alive"], KEEP_ALIVE);
        assert_eq!(payload["stream"], true);
        assert_eq!(payload["think"], false);
        let threads = payload["options"]["num_thread"].as_u64().unwrap();
        assert!((2..=8).contains(&threads), "{threads}");
        assert!(payload.get("tools").is_none());
    }

    #[test]
    fn warm_up_primes_exactly_the_reply_prefix_and_carries_no_turns() {
        let tools = json!([{"name": "log_mood_entry", "description": "Save a mood check-in.",
            "parameters": {"type":"object"}}]);
        let warm = prepare(
            json!({"system": "Neura charter", "tools": tools, "warm": true})
                .to_string()
                .as_bytes(),
        )
        .unwrap();
        let reply = prepare(
            json!({"system": "Neura charter", "tools": tools,
                "messages": [{"role":"user","content":"Hello"}]})
            .to_string()
            .as_bytes(),
        )
        .unwrap();
        assert_eq!(
            warm["messages"],
            json!([{"role":"system","content":"Neura charter"}])
        );
        assert_eq!(warm["messages"][0], reply["messages"][0]);
        assert_eq!(warm["tools"], reply["tools"]);
        assert_eq!(warm["options"]["num_predict"], 1);
        assert_eq!(warm["options"]["num_ctx"], reply["options"]["num_ctx"]);
        assert_eq!(
            warm["options"]["num_thread"],
            reply["options"]["num_thread"]
        );
        assert_eq!(warm["keep_alive"], KEEP_ALIVE);
        // A warm-up never carries conversation text, a cue or a reply cap.
        for extra in [
            json!({"messages": [{"role":"user","content":"Hello"}]}),
            json!({"cue": "Likely mood: calm."}),
            json!({"max_tokens": 64}),
        ] {
            let mut request = json!({"system": "Neura charter", "warm": true});
            request
                .as_object_mut()
                .unwrap()
                .extend(extra.as_object().unwrap().clone());
            assert!(prepare(request.to_string().as_bytes()).is_err(), "{extra}");
        }
        assert!(prepare(br#"{"system":"","warm":true}"#).is_err());
    }

    #[test]
    fn spoken_replies_may_ask_for_a_shorter_bounded_cap() {
        let request = |max: Value| {
            json!({"system": "Neura charter", "max_tokens": max,
                "messages": [{"role":"user","content":"Hello"}]})
            .to_string()
            .into_bytes()
        };
        assert_eq!(
            prepare(&request(json!(200))).unwrap()["options"]["num_predict"],
            200
        );
        assert_eq!(
            prepare(&request(json!(MIN_MAX_TOKENS))).unwrap()["options"]["num_predict"],
            MIN_MAX_TOKENS
        );
        for bad in [
            json!(0),
            json!(MIN_MAX_TOKENS - 1),
            json!(NUM_PREDICT + 1),
            json!(-5),
        ] {
            assert!(prepare(&request(bad.clone())).is_err(), "{bad}");
        }
    }

    #[test]
    fn the_larger_model_needs_enough_physical_cores() {
        assert!(!large_cores_admitted(None));
        assert!(!large_cores_admitted(Some(4)));
        assert!(!large_cores_admitted(Some(LARGE_MIN_PHYSICAL_CORES - 1)));
        assert!(large_cores_admitted(Some(LARGE_MIN_PHYSICAL_CORES)));
        assert!(large_cores_admitted(Some(16)));
    }

    #[test]
    fn cue_follows_the_newest_turn_so_the_cached_prefix_survives() {
        let request = |cue: &str| {
            json!({"system": "Neura charter", "cue": cue, "messages": [
                {"role":"user","content":"Earlier"},
                {"role":"assistant","content":"Reply"},
                {"role":"user","content":"Newest"},
            ]})
            .to_string()
            .into_bytes()
        };
        let calm = prepare(&request("Likely mood: calm.")).unwrap();
        let tense = prepare(&request("Likely mood: tense.")).unwrap();
        let messages = calm["messages"].as_array().unwrap();
        assert_eq!(messages.len(), 5);
        assert_eq!(messages[0]["content"], "Neura charter");
        assert_eq!(messages[3]["content"], "Newest");
        assert_eq!(
            messages[4],
            json!({"role":"system","content":"Likely mood: calm."})
        );
        // Everything before the cue is byte-identical across different cues.
        assert_eq!(messages[..4], tense["messages"].as_array().unwrap()[..4]);
        // No cue, or a blank one, adds no message.
        for cue in ["", "  "] {
            assert_eq!(
                prepare(&request(cue)).unwrap()["messages"]
                    .as_array()
                    .unwrap()
                    .len(),
                4
            );
        }
        assert!(prepare(&request(&"x".repeat(MAX_CUE_BYTES + 1))).is_err());
    }

    fn tool_request(messages: Value) -> Vec<u8> {
        json!({"system": "Neura charter", "messages": messages, "tools": [{
            "name": "log_mood_entry", "description": "Save a mood check-in.",
            "parameters": {"type":"object","properties":{"mood0to10":{"type":"integer"}}}
        }]})
        .to_string()
        .into_bytes()
    }

    #[test]
    fn tools_and_a_tool_round_are_forwarded_in_ollama_form() {
        let payload = prepare(&tool_request(json!([
            {"role":"user","content":"Log my mood as 7"},
            {"role":"assistant","content":"","tool_calls":[
                {"name":"log_mood_entry","arguments":{"mood0to10":7}}]},
            {"role":"tool","content":"Saved 7/10.","tool_name":"log_mood_entry"},
        ])))
        .unwrap();
        assert_eq!(payload["tools"][0]["type"], "function");
        assert_eq!(payload["tools"][0]["function"]["name"], "log_mood_entry");
        let messages = payload["messages"].as_array().unwrap();
        assert_eq!(
            messages[2]["tool_calls"][0]["function"]["arguments"]["mood0to10"],
            7
        );
        assert_eq!(messages[3]["role"], "tool");
        assert_eq!(messages[3]["tool_name"], "log_mood_entry");
    }

    #[test]
    fn unadvertised_or_malformed_tool_use_is_rejected() {
        for messages in [
            // A call to a tool the request did not advertise.
            json!([{"role":"user","content":"x"},
                {"role":"assistant","content":"","tool_calls":[
                    {"name":"delete_files","arguments":{}}]},
                {"role":"tool","content":"x","tool_name":"delete_files"}]),
            // A tool result without a tool name, or on a user turn.
            json!([{"role":"user","content":"x"},{"role":"tool","content":"x"}]),
            json!([{"role":"user","content":"x","tool_name":"log_mood_entry"}]),
            // The conversation must end on a user or tool turn.
            json!([{"role":"user","content":"x"},{"role":"assistant","content":"y"}]),
        ] {
            assert!(prepare(&tool_request(messages)).is_err());
        }
        // Path-like or oversized tool definitions are refused outright.
        for tool in [
            json!({"name":"../x","description":"d","parameters":{}}),
            json!({"name":"ok","description":"d".repeat(601),"parameters":{}}),
            json!({"name":"ok","description":"d","parameters":"not an object"}),
        ] {
            let raw = json!({"system":"s","messages":[{"role":"user","content":"x"}],
                "tools":[tool]});
            assert!(prepare(raw.to_string().as_bytes()).is_err());
        }
    }

    #[tokio::test]
    async fn streamed_tool_call_returns_an_envelope() {
        use axum::{routing::post, Json};
        let router = crate::local_model::tests::metadata_router()
            .route("/api/show", post(|| async { Json(local_info()) }))
            .route(
                "/api/chat",
                post(|Json(request): Json<Value>| async move {
                    assert!(request["tools"].is_array());
                    axum::body::Body::from(ndjson(json!({"done": true, "message": {
                        "role": "assistant", "content": "",
                        "tool_calls": [{"function": {"name": "log_mood_entry",
                            "arguments": {"mood0to10": 7}}}]}})))
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        let payload = prepare(&tool_request(json!([{"role":"user","content":"Log 7"}]))).unwrap();
        let (envelope, _) = timed_inference(
            &endpoint,
            payload,
            &Mutex::new(RequestTiming::default()),
            |_| true,
            false,
        )
        .await
        .unwrap();
        let envelope: Value = serde_json::from_str(&envelope).unwrap();
        assert_eq!(envelope["text"], "");
        assert_eq!(envelope["tool_calls"][0]["name"], "log_mood_entry");
        assert_eq!(envelope["tool_calls"][0]["arguments"]["mood0to10"], 7);
        server.abort();
    }

    #[test]
    fn residency_relaxes_only_the_available_memory_floor() {
        let mut s = Session::default();
        s.state.lock().unwrap().foreground = true;
        assert!(!s.resident_now());
        s.state.lock().unwrap().resident_until = Some(Instant::now() + RESIDENCY_TRUST);
        assert!(s.resident_now());
        s.state.lock().unwrap().resident_until = Some(Instant::now() - Duration::from_secs(1));
        assert!(!s.resident_now());
        // A memory rejection still creates no worker, resident or not.
        assert_eq!(s.begin_checked(json!({}), || false), -4);
        assert!(s.active.is_none());
    }

    #[test]
    fn peek_returns_streamed_text_only_for_the_current_generation() {
        let _global = GLOBAL_SESSION.lock().unwrap_or_else(|p| p.into_inner());
        let mut s = Session::default();
        {
            let mut state = s.state.lock().unwrap();
            state.generation = 5;
            state.foreground = true;
            state.status = 0;
            state.partial = Some(Zeroizing::new(b"Hello th".to_vec()));
        }
        *session().lock().unwrap() = std::mem::take(&mut s);
        let mut buffer = [0u8; 16];
        // SAFETY: each call advertises this live buffer's real size.
        unsafe {
            assert_eq!(neura_ollama_peek(5, buffer.as_mut_ptr(), buffer.len()), 8);
            assert_eq!(&buffer[..8], b"Hello th");
            assert_eq!(neura_ollama_peek(4, buffer.as_mut_ptr(), buffer.len()), -2);
            assert_eq!(neura_ollama_peek(5, buffer.as_mut_ptr(), 4), -1);
            assert_eq!(neura_ollama_peek(5, std::ptr::null_mut(), 16), -1);
        }
        neura_ollama_cancel(5);
        // SAFETY: same live buffer; cancellation revoked the generation.
        assert_eq!(
            unsafe { neura_ollama_peek(5, buffer.as_mut_ptr(), buffer.len()) },
            -2
        );
        assert!(session()
            .lock()
            .unwrap()
            .state
            .lock()
            .unwrap()
            .partial
            .is_none());
        *session().lock().unwrap() = Session::default();
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
            json!({"system":"x","messages":[{"role":"user","content":"x".repeat(MAX_HISTORY_BYTES + 1)}]})
                .to_string()
                .as_bytes()
        )
        .is_err());
    }
    #[test]
    fn background_and_block_prevent_admission_and_clear_reply() {
        let mut s = Session::default();
        assert_eq!(s.begin(json!({})), -2);
        assert_eq!(s.begin_readiness(), -2);
        {
            let mut state = s.state.lock().unwrap();
            state.foreground = true;
            state.blocked = true;
            state.reply = Some(Zeroizing::new(b"private".to_vec()));
            state.readiness = Some([1, 1, 1, 1, 1, 8192, 4096]);
        }
        s.cancel();
        assert!(s.state.lock().unwrap().reply.is_none());
        assert!(s.state.lock().unwrap().readiness.is_none());
        assert_eq!(s.begin(json!({})), -2);
        assert_eq!(s.begin_readiness(), -2);
        assert!(s.active.is_none());
    }

    #[test]
    fn readiness_preserves_memory_thresholds_and_unknown_is_not_admitted() {
        for (memory, expected) in [
            (None, [0, 0, 0]),
            (Some((7168, 3584)), [1, 7168, 3584]),
            (Some((7167, 4096)), [2, 7167, 4096]),
            (Some((8192, 3583)), [2, 8192, 3583]),
        ] {
            let model = crate::local_model::ModelReadiness {
                daemon: 1,
                version: 1,
                model: 1,
            };
            let report = readiness_snapshot(model, memory);
            assert_eq!(&report[..4], &[1, 1, 1, 1]);
            assert_eq!(&report[4..], &expected);
        }
    }

    #[test]
    fn readiness_cannot_replace_an_active_worker() {
        let mut s = Session::default();
        s.state.lock().unwrap().foreground = true;
        let (cancel, _) = watch::channel(false);
        let (release, gate) = std::sync::mpsc::channel();
        s.active = Some(Active {
            cancel,
            worker: std::thread::spawn(move || {
                let _ = gate.recv();
            }),
        });
        assert_eq!(s.begin_readiness(), -3);
        release.send(()).unwrap();
        s.active.take().unwrap().worker.join().unwrap();
    }

    #[tokio::test]
    async fn readiness_cancel_drops_a_pending_metadata_request() {
        use axum::{routing::post, Json};
        let entered = Arc::new(tokio::sync::Notify::new());
        let seen = entered.clone();
        let router = crate::local_model::tests::metadata_router().route(
            "/api/show",
            post(move || {
                let seen = seen.clone();
                async move {
                    seen.notify_one();
                    tokio::time::sleep(Duration::from_secs(30)).await;
                    Json(crate::local_model::tests::pinned_info())
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        let (cancel, mut receiver) = watch::channel(false);
        let worker =
            tokio::spawn(async move { cancellable_readiness(&endpoint, &mut receiver).await });
        tokio::time::timeout(Duration::from_secs(2), entered.notified())
            .await
            .unwrap();
        cancel.send_replace(true);
        assert!(tokio::time::timeout(Duration::from_millis(200), worker)
            .await
            .unwrap()
            .unwrap()
            .is_err());
        server.abort();
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
        let _global = GLOBAL_SESSION.lock().unwrap_or_else(|p| p.into_inner());
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
        assert_eq!(neura_ollama_readiness_begin(), -2);
        let mut readiness = [0u64; READINESS_FIELDS];
        // SAFETY: each call below advertises this live aligned output array.
        unsafe {
            assert_eq!(
                neura_ollama_readiness_poll(100, std::ptr::null_mut(), readiness.len()),
                -1
            );
            assert_eq!(
                neura_ollama_readiness_poll(100, readiness.as_mut_ptr(), 1),
                -1
            );
            assert_eq!(
                neura_ollama_readiness_poll(100, readiness.as_mut_ptr(), readiness.len()),
                -2
            );
        }
        assert_eq!(readiness, [0; READINESS_FIELDS]);
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
    /// One Ollama NDJSON stream line.
    fn ndjson(value: Value) -> String {
        format!("{value}\n")
    }
    fn chunk(content: &str, done: bool) -> String {
        ndjson(json!({"message":{"role":"assistant","content":content},"done":done}))
    }
    async fn mock(
        info: Value,
        answer: String,
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
                    assert_eq!(request["keep_alive"], KEEP_ALIVE);
                    assert_eq!(request["stream"], true);
                    assert_eq!(request["think"], false);
                    assert!(request.get("tools").is_none());
                    axum::body::Body::from(answer)
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
        let answer = [
            chunk("Hi, ", false),
            chunk("I'm Neura.", false),
            chunk("", true),
        ]
        .concat();
        let (endpoint, calls, task) = mock(local_info(), answer.clone()).await;
        let mut deltas = Vec::new();
        // The larger model is requested but not installed: the standard pin
        // serves the reply (the mock asserts the request names LOCAL_MODEL).
        let (text, large) = timed_inference(
            &endpoint,
            payload(),
            &Mutex::new(RequestTiming::default()),
            |delta| {
                deltas.push(delta.to_owned());
                true
            },
            true,
        )
        .await
        .unwrap();
        assert!(!large);
        assert_eq!(text, "Hi, I'm Neura.");
        assert_eq!(deltas, ["Hi, ", "I'm Neura."]);
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
    async fn installed_large_model_is_verified_and_used() {
        use axum::{routing::get, routing::post, Json, Router};
        let tags = json!({"models":[
            {"name": STANDARD_PIN.tag, "digest": &STANDARD_PIN.manifest_digest[7..]},
            {"name": LARGE_PIN.tag, "digest": &LARGE_PIN.manifest_digest[7..]},
        ]});
        let router = Router::new()
            .route(
                "/api/version",
                get(|| async { Json(json!({"version":"0.18.0"})) }),
            )
            .route("/api/tags", get(move || async move { Json(tags) }))
            .route(
                "/api/show",
                post(|Json(request): Json<Value>| async move {
                    let pin = if request["model"] == LARGE_PIN.local_tag {
                        LARGE_PIN
                    } else {
                        STANDARD_PIN
                    };
                    Json(json!({"details":{"family":pin.family,
                        "parameter_size":pin.parameter_size,
                        "quantization_level":pin.quantization}}))
                }),
            )
            .route(
                "/api/chat",
                post(|Json(request): Json<Value>| async move {
                    assert_eq!(request["model"], LARGE_PIN.local_tag);
                    axum::body::Body::from(
                        [chunk("Bigger ", false), chunk("answer.", true)].concat(),
                    )
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        let (text, large) = timed_inference(
            &endpoint,
            payload(),
            &Mutex::new(RequestTiming::default()),
            |_| true,
            true,
        )
        .await
        .unwrap();
        assert!(large);
        assert_eq!(text, "Bigger answer.");
        server.abort();
    }

    #[test]
    fn large_pin_is_the_reviewed_manifest() {
        assert_eq!(LARGE_PIN.tag, "qwen3:8b");
        assert_eq!(LARGE_PIN.local_tag, "qwen3:8b:local");
        assert_eq!(
            LARGE_PIN.manifest_digest,
            "sha256:500a1f067a9f782620b40bee6f7b0c89e17ae61f686b92c24933e4ca4b2b8b41"
        );
        assert_eq!(
            (
                LARGE_PIN.family,
                LARGE_PIN.parameter_size,
                LARGE_PIN.quantization
            ),
            ("qwen3", "8.2B", "Q4_K_M")
        );
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
            let result = cancellable_inference(
                &endpoint,
                payload(),
                &worker_timing,
                &mut receiver,
                |_| true,
                false,
            )
            .await;
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
    #[test]
    fn capped_reply_ends_at_its_last_complete_sentence() {
        for (cut, want) in [
            (
                "That sounds really hard. Want to talk it thro",
                "That sounds really hard.",
            ),
            ("I hear you! Is it work? Or some", "I hear you! Is it work?"),
            (
                "She said \"rest first.\" Then we can pla",
                "She said \"rest first.\"",
            ),
            (
                "Small steps help, e.g. a short walk. Dr. Lee and I agr",
                "Small steps help, e.g. a short walk.",
            ),
            (
                "Some ideas.\n\n1. Drink water\n2. Step outside\n3. Ca",
                "Some ideas.\n\n1. Drink water\n2. Step outside",
            ),
            (
                "That makes sense. Here are a few things to try:\n\n- Bre",
                "That makes sense.",
            ),
            ("Okay. **Try these:**\n1. Slow", "Okay."),
            (
                "You did well.\n\n## Next steps\nRest a lit",
                "You did well.",
            ),
            (
                "It is okay to feel tired and want to rest for a whi",
                "It is okay to feel tired and want to rest for a\u{2026}",
            ),
            ("Rest, then", "Rest\u{2026}"),
            ("Great\u{2026} let me thi", "Great\u{2026}"),
        ] {
            assert_eq!(finish_at_sentence(cut), want, "{cut:?}");
        }
    }
    #[tokio::test]
    async fn only_a_capped_reply_is_shortened() {
        let text = "That sounds hard. Want to tal";
        for (reason, want) in [("length", "That sounds hard."), ("stop", text)] {
            let (first, rest) = text.split_at(10);
            let answer = chunk(first, false)
                + &ndjson(json!({"done":true,"done_reason":reason,
                    "message":{"role":"assistant","content":rest}}));
            let (endpoint, _, task) = mock(local_info(), answer).await;
            assert_eq!(inference(&endpoint, payload()).await.unwrap(), want);
            task.abort();
        }
    }
    #[tokio::test]
    async fn rejects_tool_calls_incomplete_and_oversized_replies() {
        for answer in [
            ndjson(
                json!({"done":true,"message":{"role":"assistant","content":"x","tool_calls":[{}]}}),
            ),
            chunk("x", false),
            [chunk("x", false), ndjson(json!({"error":"boom"}))].concat(),
            ndjson(json!({"done":true,"remote_host":"https://ollama.com",
                "message":{"role":"assistant","content":"x"}})),
            (0..=MAX_REPLY / 1_000)
                .map(|_| chunk(&"x".repeat(1_000), false))
                .collect::<String>(),
            chunk(&"x".repeat(STREAM_LIMITS.max_line), true),
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
        let response = crate::http_client::builder()
            .no_proxy()
            .build()
            .unwrap()
            .get(endpoint)
            .send()
            .await
            .unwrap();
        let result = tokio::time::timeout(
            Duration::from_secs(2),
            crate::local_model::bounded_json(response, 32_768),
        )
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
