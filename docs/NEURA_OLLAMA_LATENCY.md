# Private Ollama response measurements

Review candidate based on PR #136 at `187d56b3e9c4c3a286027b247d5fd479b5b049f6`.
No measured response-speed improvement is claimed. No automatic merge.

## Implemented boundary

The existing Rust Ollama adapter records one latest request's monotonic durations.
The Windows owner exposes a read-only, fixed numeric snapshot. The existing
`NeuraOllamaChat.readLatency()` combines those durations with the Dart request's
total and cancellation cleanup time. Reading a snapshot starts no work, does not
wait for model completion and returns null after lifecycle/privacy invalidation.
This is a diagnostics API; no diagnostic panel or automatic export is added.

There is no sample history, prompt/reply/credential/error text, wall-clock date,
user identifier, file write, telemetry sink, periodic sampler or background
inference in the app. A new request replaces the prior sample. Backgrounding,
window deactivation, Safe Mode, recovery and shutdown erase native timing.
Flutter also clears its latest sample on background, safety, recovery and chat
disposal. Explicit `clearLatency()` erases both copies. An in-flight read cannot
resurrect a cleared or superseded sample. Caller-owned copies cannot be revoked;
consumers must keep them session-only and respect the same lifecycle boundaries.

| Field | Measurement boundary |
| --- | --- |
| `preflight` | Native admission to client setup and validated `/api/show` model metadata. It includes worker/runtime startup. A preflight failure/cancellation records its partial elapsed duration through teardown. |
| `inference` | Validated metadata to verified reply and worker/runtime teardown; includes `/api/chat`, bounded body decoding and reply validation. On inference failure/cancellation this is a partial phase. |
| `delivery` | Verified native reply ready to its one-time poll buffer copy; includes the existing 100 ms polling cadence. It excludes the Windows-to-Dart bridge and rendered frame. |
| `nativeCancellation` | First native cancellation signal to the owned request future/runtime teardown. Zero is valid if the worker already finished and only a queued reply is discarded. Pending cleanup is null. It does not measure cessation of the user-owned Ollama daemon's compute. |
| `nativeTotal` | Native admission to poll copy, failed-worker cleanup or cancelled-worker cleanup. Null while the terminal boundary is pending. |
| `total` | Dart submission before JSON encoding to final adapter cleanup before return/throw. Includes admission, bridges and polling; excludes caller guardrails, Flutter frame presentation and speech. |
| `cancellation` | Dart observation of cancellation to adapter cleanup completion, including a late native begin acknowledgement and the best-effort native cancel call. This is distinct from native worker teardown. |

Missing/unreached phases are null, never zero-valued success samples. Native and
Dart use independent monotonic epochs; their durations must not be summed.
Outcomes are fixed enum values: running, delivered, failed, cancelled. The native
ABI also distinguishes a ready reply awaiting delivery. No request id is part of
the returned Dart record. Timing collection does not change model/profile,
timeouts, polling cadence, connection policy, prompt, token limits or residency.

The native ABI `neura_ollama_timing(id, uint64_buffer, capacity)` returns seven
u64 fields: version 1, outcome, preflight/inference/delivery/cancellation/total
microseconds. `UINT64_MAX` means unavailable. Reads reject short/null buffers,
wrong ids, blocked/background sessions and cleared/replaced records. Cancellation
can be inspected using the original request id until the next request or clear.
The native owner performs no DLL load or foreground reactivation to read timing.

Local endpoint/model validation, no proxies/redirects/cloud fallback, the 7 GiB
total and 3.5 GiB available-RAM gate, `keep_alive: 0`, cancellation and credential
boundaries remain enforced. No automatic model download or API-key access is
introduced. Cancellation during the final bridge-cleanup await now suppresses
an already-polled reply before returning it to the caller.

## Controlled Windows comparison

The optional `tools/benchmark_ollama_latency.py` is separate from the app. It runs
only when explicitly invoked on Windows with both DLL paths and confirmation
that Neura/model chats are closed. It refuses a host with any Up network adapter;
it never changes adapters, installs tools/models, or runs as a service/automation.
Do not disconnect a CI runner to make this precondition pass.

Build baseline and candidate DLLs on the same authorized Windows machine using
the same Rust toolchain, locked dependencies and release profile:

- Baseline A: `a4e8c5e793d4aa3764c66a47819c395b555c786b`, before PR #136.
- Candidate B: this review branch, including PR #136 and timing instrumentation.
- To isolate instrumentation overhead, also compare PR #136's unchanged head
  `187d56b3e9c4c3a286027b247d5fd479b5b049f6` with this branch.
- In each separate checkout run `cargo build --manifest-path rust/Cargo.toml --locked --release --lib`.
  Keep each resulting `rust/target/release/neura_swarm.dll` in its own directory.

After manual Ollama/model setup, close Neura and all model chats. Disconnect the
test machine from networks, leaving loopback available. Keep the same CPU/power
mode, background applications and available RAM. Then, in foreground PowerShell
with 64-bit Python 3.12 or newer:

```powershell
python tools/benchmark_ollama_latency.py --baseline C:\NeuraBaseline\neura_swarm.dll --candidate C:\NeuraCandidate\neura_swarm.dll --rounds 10 --idle-confirmed
```

The harness uses the real native ABI and memory-admission gate. It alternates
baseline/candidate order in isolated child processes and sends the same three
synthetic questions (arithmetic, a short plan, uncertainty), ten rounds each.
It checks `/api/ps` for an unloaded model and verifies the same fixed model's
digest from `/api/tags` before/after each trial. These bounded, loopback-only
metadata checks never contain conversation text. All inference stays in the
existing adapter. Both builds retain the same `keep_alive: 0` policy.

Numeric stdout includes per-trial outcome, attempt duration, successful response
p50/p95 with sample counts, model/binary digests, RAM at admission and a sampled
combined peak working set for the trial host plus the Ollama process tree.
The temporary memory-sampling thread exists only during that foreground trial;
it is never installed in Neura. A 20 ms sampled working-set peak is a lower
bound, can double-count shared pages and excludes GPU memory/private commit.
Incomplete sampling is explicitly counted. Do not call it an exact memory peak
or compare runs with missing samples or `conditions_match: false` (including
available-RAM variation above 128 MiB). DLL host memory is not Flutter app memory.
The baseline lacks native phase timing; its missing phase values stay null.

The harness writes no files and prints no prompts, replies, daemon errors,
process identities or credentials. Output persists only if the operator chooses
to save it. Failed/admission-rejected trials are counted separately and cannot
improve latency percentiles. Narrow quality checks count arithmetic correctness,
plan line structure and uncertainty language. These heuristics cannot establish
answer usefulness or safety; manually compare relevance, correctness, Neura's
tone, uncertainty and safety using synthetic examples. Record differences as
ratings/labels without retaining conversation text. Do not claim a gain from
the instruction model's `think: false` setting without that comparison.

Separately exercise Stop, barge-in, focus loss, chat closure, Safe Mode, recovery
and app exit while a reply is pending. Read the foreground cancellation snapshot
only for explicit Stop; lifecycle/safety clears intentionally leave no receipt.
Observe daemon compute cessation separately. To measure actual laptop UI latency
and RAM, repeat in the packaged app, recording submit-to-visible response time
and combined Neura/Ollama working set. The DLL harness excludes Flutter frames,
guardrails and TTS, so it cannot stand in for physical-laptop UI acceptance.

## Evidence status

Automated validation and real-device performance are separate. Synthetic timing
fixtures use prescribed durations; they prove accounting, not model speed.

| Evidence | Result |
| --- | --- |
| Rust deterministic phase tests and loopback/model/cancellation regressions | Passed in Linux authoring environment; exact test commands recorded in the PR. |
| Existing Rust credential, lifecycle and memory boundaries | Covered by the full locked Rust test suite and strict Clippy. |
| Flutter adapter/lifecycle and deterministic injected-clock tests | Validation in progress; see PR checks for the final result. |
| Benchmark statistics and fixed quality rubric | Five automated Python tests passed; no real model invoked. |
| Packaged Windows ABI/launch | New timing exports and blocked timing reads added to the existing verifier; Windows execution pending. |
| Baseline/candidate response speed, peak RAM, failures and answer-quality differences on an actual laptop | Not measured. No authorized, controlled offline Windows/Ollama measurement session was established during authoring. Existing Windows Local Runner success on PR #136 was build/test evidence. |

No performance threshold, optimization claim or release-readiness conclusion can
be inferred from synthetic durations, source inspection or an earlier build.
