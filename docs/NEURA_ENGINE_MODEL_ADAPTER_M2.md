# Neura Engine milestone 2: opt-in local model adapter (first slice)

This slice replaces the sidecar's echo-only model path with an **explicitly
selected, pinned local model adapter** and makes diagnostics distinguish the
three modes the [engine vision](NEURA_ENGINE_VISION.md#implementation-milestones)
requires: echo/test, real local model, and unavailable. It does not complete
milestone 2, admit personal sources, enable reflection, or change the default.

The [milestone 1 IPC contract](NEURA_ENGINE_IPC_M1.md) is unchanged: same
authentication, loopback binding, envelope framing, queue/frame budgets,
cancellation, revocation and `input_scope: synthetic-only`.

## Selecting the adapter

`neura_api` reads `NEURA_API_MODEL_ADAPTER` once at startup:

| Value | Adapter |
| --- | --- |
| absent or `echo` | Default. Fixed repository echo text; diagnostics report the degraded echo adapter exactly as before. |
| `ollama-local` | The pinned model on the operator's loopback Ollama daemon. |
| anything else | The process exits before binding. The value is never logged. |

The adapter cannot be changed over IPC, by a URL, or per request. The Windows
native launcher sets it only through the Console's explicit local model check
(below); an ordinary start still passes no adapter variable and uses echo.

## Console local model check

The Console has an optional **Local model** section. Its **Start local model
check** button stays disabled until the operator ticks an acknowledgement that
they installed the pinned model themselves and want the check to use it. The
acknowledgement lives only in that screen's session object: it is never
persisted, closing the screen discards it, and Safe Mode or recovery clears it
and blocks new starts.

| Layer | Behavior |
| --- | --- |
| Flutter `EngineSession.startLocal()` | Does nothing without the acknowledgement; otherwise sends the argument-free `startLocalCheck` method. |
| Windows bridge | `startLocalCheck` calls the new `neura_engine_start_local_check` export. The bridge requires that export, so an older DLL fails closed as `unavailable`. |
| Native launcher | Adds exactly `NEURA_API_MODEL_ADAPTER=ollama-local` to the restricted child environment for that session. Pause and Resume keep the session's adapter; Start cannot bypass Pause in either mode. |
| Native probe | Checks `hello` reports `model_adapter: ollama-local`, then diagnostics before any fixture. `model_mode: unavailable` ends the session as `model_unavailable` without submitting the fixture. Otherwise it runs the fixed hello and accepts any non-empty completion; the model text is never retained or delivered to Flutter. |

The local check has its own budgets because a cold model load is slow: a
75-second outer probe deadline (diagnostics, preflight and the sidecar's
60-second request deadline, which already includes model loading)
and up to 200 response frames (192 predicted tokens, each possibly its own
delta, plus the completion). Exhausting either pauses the session, as in the
echo check. A run-time `error` with an unavailable code maps to
`model_unavailable`; a budget or timeout error maps to exhaustion; any other
error is a failure.

Native status slot 8 is `model_unavailable`. Flutter shows it with what the
operator needs to do (use a supported Ollama release and the reviewed model) and treats it
like `unavailable`: the session is stopped and a new explicit start is
required.

## The pinned model

`rust/src/local_model.rs` is now the single contract shared by the Windows chat
adapter (#127) and the sidecar:

- Tag `qwen3:4b-instruct`, requested as `qwen3:4b-instruct:local` so Ollama
  rejects remote aliases at execution time.
- Stable Ollama version **0.18.0 or newer** is required. `/api/version` is
  checked before model lookup; older, malformed, unknown or prerelease versions
  fail closed as `unsupported_version`. This is a conservative source-checked
  floor, not a claim that every admitted version has passed Windows device tests.
- `/api/tags` must report the reviewed manifest digest
  `sha256:0edcdef34593eac1aa2be9c7d06c432dcf81945adca5eca2f27662c18f168ba0`
  for this exact tag. Both Ollama's normal bare-hex digest and the `sha256:`
  representation are accepted; a different digest fails as `model_mismatch`.
- Metadata must report family `qwen3`, parameter size `4.0B`, quantization
  `Q4_K_M`, and no `remote_host`/`remote_model`. `/api/show` also uses the
  explicit `:local` identifier, consistently with `/api/chat`.
- Fixed endpoint `http://127.0.0.1:11434`, no proxy, no redirects, 2-second
  connect deadline. `LoopbackClient` is the only way the module reaches a
  daemon and accepts only numeric loopback `http://` endpoints, so neither
  verification nor chat can be pointed at a LAN, public or DNS host.
- Windows admission budget: at least 7 GiB installed and 3.5 GiB available
  memory. Other platforms are not admitted. This is an admission estimate,
  not an enforced memory cap on the separately owned Ollama process. The
  one-run permit applies to one sidecar process, not every Ollama client.

Neura never installs, downloads, pulls, starts or stops a model or the daemon.
Installing Ollama and the pinned model is the operator's explicit choice.
There is no echo, alternative-model or cloud fallback once `ollama-local` is
selected: an unverifiable model is reported as unavailable and refuses work.

The daemon remains a trusted local dependency. Its version and digest are
self-reported; the tag is resolved separately for tags, show and chat. This
preflight detects an already replaced tag, but does **not** provide atomic
digest-bound execution or attest the files read by the runner. A concurrent
local-weight swap remains a trust/acceptance limitation; the unresolved PR
review on immutable identity is only partially mitigated. Do not describe this
as immutable weight verification. The `:local` guard independently rejects a
remote alias at request execution in the inspected Ollama implementations.

## Diagnostics

`diagnostics` keeps its v1 shape and adds `model_mode`:

| `model_mode` | Model adapter check | Meaning |
| --- | --- | --- |
| `echo` | `degraded` | Default echo provider (unchanged text). |
| `local` | `ok` | Admission passed and the pinned model verified just now. |
| `unavailable` | `unavailable` + `code` | Opted in, but the model cannot be used. |

Unavailable codes: `unreachable`, `unsupported_version`, `not_installed`, `remote_model`,
`model_mismatch`, `malformed_metadata`, `insufficient_memory`. They never
include daemon output.

For the local adapter, diagnostics also report the reviewed `model` identity,
manifest digest, minimum daemon version, and a content-free `last_run` record:
fixture name, outcome (`completed`,
`cancelled`, `failed`, `exhausted`, `unavailable`), time to first token,
total time and output byte count. No prompt or model text is retained or
reported. These are the per-run measurements milestone 2 needs for supported
hardware evidence.

A local-adapter diagnostics request runs the probe as an owned task (3-second
deadline) so the connection keeps reading `cancel`; a second request while one
is active is rejected, not queued. `hello` now also reports the configured
`model_adapter` (`echo` or `ollama-local`) and version `0.4.0`.

## Local runs

`synthetic_input` still accepts only the `hello` and `stream` fixtures. With
the local adapter each fixture maps to a fixed, repository-defined
instruction; caller text never reaches the model.

Each run:

1. Re-verifies admission and the pinned model (a tag can be replaced after a
   diagnostics check). Failure returns a content-free `error` with its `code`
   and submits no prompt.
2. Streams `/api/chat` (`stream: true`, `keep_alive: 0`, `num_ctx` 2048,
   `num_predict` 192, `num_thread` 2, no tools).
3. Forwards text as `speak_delta`. The first delta is sent immediately; later
   deltas are coalesced to at least 48 bytes or 60 ms so a fast model cannot
   outrun the bounded 32-message outbound queue.
4. Sends `speak` with the full text only after Ollama's final `done` line.

| Limit | Behavior |
| --- | --- |
| 3 s probe deadline | Reported as `unreachable`. |
| 60 s run deadline | `error` "model request timed out"; outcome `exhausted`. |
| 4 KiB per streamed line, 3,000 bytes total text, 64 KiB response body | `error` "model output exceeded budget"; outcome `exhausted`. The body budget is checked before each chunk is buffered. |
| Any delta or final frame over 4 KiB after JSON escaping | Same budget error; no `speak`, and the connection stays open. |
| Remote model, tool call, `error` line, malformed line, or no `done` | `error` "model request failed"; no `speak`. |
| One run per connection | Overlapping work receives "synthetic work already active". |
| One local run per process | A run from another client while one is active receives "local model busy"; nothing is queued. The permit is released when the run ends, including by cancel or revocation. |

`cancel`, revocation, a stalled writer or queue exhaustion abort the run task,
which drops the HTTP response and closes the connection to Ollama. The run is
recorded as `cancelled` with the
TTFT and output size observed so far; the record is created before the task is
spawned, so even a run aborted before it starts is recorded. No late completion
is delivered or replayed.

This proves request teardown and suppression of late results, not immediate
cessation of the external runner's computation or release of its RAM/VRAM.
Measure those separately on Windows; Neura does not kill the operator's daemon.

## Validation

```text
cargo test --manifest-path rust/Cargo.toml --locked
cargo clippy --manifest-path rust/Cargo.toml --locked --all-targets -- -D warnings
flutter test test/neura_link/engine_session_lifecycle_test.dart
rustfmt --edition 2021 --check rust/src/bin/neura_api.rs rust/src/ipc_tests.rs rust/src/local_model.rs rust/src/ollama_conversation.rs
```

The sidecar suite runs the real authenticated WebSocket server against a
loopback mock Ollama and covers: explicit adapter selection; verified
streaming with only the fixed prompt submitted; content-free metrics;
remote and mismatched models reported unavailable with zero chat requests;
absent daemon and memory-budget refusal; cancellation and revocation dropping a
hung model response; over-budget, incomplete and tool-call output; and
overlapping work rejection. The existing echo, authorization, revocation and
transport-exhaustion tests pass unchanged.

The native lifecycle suite launches real sidecars through both spawn plans and
checks that only the local entry point starts one whose `hello` reports
`ollama-local`; this never contacts Ollama. Where no daemon can answer (any
non-Windows host, or nothing listening on the Ollama port), it also runs the
whole local check and requires `model_unavailable`. Tests never load a real
model: on a host that could serve one, that test stops right after launch. It
also checks that Resume keeps the adapter and, with controlled loopback peers,
that the probe accepts a verified completion, reports unavailable models before
submitting a fixture, maps run errors, rejects an echo sidecar, and pauses at
the frame budget. Flutter tests cover the acknowledgement gate, argument-free
calls, the `model_unavailable` stop, Safe Mode clearing the acknowledgement, and
the Console checkbox.

## Collecting device evidence

`tools/Collect-NeuraEngineEvidence.ps1` gathers the hardware measurements this
milestone needs with one command. Start Ollama yourself, then run:

```text
.\tools\Collect-NeuraEngineEvidence.ps1 -ConfirmLocalModel -Runs 3
```

It builds `neura_api` and the `neura_engine_evidence` tool in release mode,
launches a sidecar with the local adapter and a fresh credential, and writes a
JSON report. The same tool runs on its own with
`neura_engine_evidence --confirm-local-model [--runs N] [--out FILE] [--sidecar PATH]`.

| Report field | What it records |
| --- | --- |
| `host` | OS, architecture, logical CPUs, total and available memory, mains power and battery percentage. |
| `model.installed` | Size and digest of the installed pinned tag from Ollama's `/api/tags`, or `null` if absent. |
| `model_mode` | `local`, or `unavailable` with `unavailable_code` (exit code 2, nothing measured). |
| `runs[]` | Per run of each fixture: outcome, client and sidecar time to first token and total time, delta frames, output bytes, peak drop in available memory, power state. |
| `summary` | Min, median and max of completed runs per fixture. |
| `cancellation` | Cancel at the first streamed delta: time until the connection closed, the recorded outcome, and time to verified output from a follow-up run (`cancel_to_next_output_ms`). This includes model latency, not just permit release. A follow-up error is a failure, not recovery evidence. |

Report schema **2** replaces the misleading `cancel_to_next_accept_ms` field.
The sidecar requests `keep_alive: 0`, asking Ollama to unload after completion.
That alone does not prove a cold load: another client may have the model
resident, and the OS file cache can remain warm. Record `/api/ps` immediately
before each cold trial, ensure other clients are idle, and distinguish unloaded
model trials from a cold OS cache. `peak_memory_delta_mib` is a 200 ms sample of
system available-memory drop, not combined per-process peak working set or VRAM.
The tool refuses to start
without the explicit confirmation, never downloads a model or starts Ollama,
and records counts and timings only, never prompt or model text. Its tests run
against a mock sidecar and, where no daemon can answer, the real sidecar; they
never load a real model.

## Remaining milestone 2 gates

- Record target-hardware evidence on supported Windows devices with the pinned
  model installed, using `tools/Collect-NeuraEngineEvidence.ps1`, on mains
  power and on battery. Mock tests are not device evidence.
- Confirm the model license and storage footprint review that the vision
  requires before selection is treated as final.
- Run the Console local model check on supported Windows hardware with the
  pinned model installed, and with it missing, and record the outcomes and
  timings. Measure whether the 75-second probe deadline is right for a cold
  load on the slowest supported device.

Personal sources, memory admission, reflection, suggestions and background
availability remain disabled (milestones 3–5).

## Review evidence — 2026-10-19

**Acceptance remains pending.** PR #140 was inspected open and unmerged at
`484310bc539dfe105af4f6c3b1e31acd12ecccbe`. This review adds a daemon-version
gate, published-manifest preflight, explicit-local show requests, and corrected
cancellation-report semantics. No model was downloaded or executed in this
Linux review environment; no Windows host with Ollama was available.

### Published model and source compatibility

| Item | Verified finding |
| --- | --- |
| Catalog identity | [qwen3:4b-instruct](https://ollama.com/library/qwen3:4b-instruct), catalog manifest prefix `0edcdef34593`, Q4_K_M, about 4.02 billion parameters (API metadata rounds to `4.0B`). |
| License | The catalog's [license layer](https://ollama.com/library/qwen3:4b-instruct/blobs/d18a5cc71b84) is Apache 2.0. Identification is verified; owner sign-off and any redistribution/notice review remain outstanding. |
| Storage | The [registry manifest](https://registry.ollama.ai/v2/library/qwen3/manifests/4b-instruct) contains a 2,497,280,480-byte model layer; config plus all layers total 2,497,293,803 bytes, about 2.50 GB / 2.33 GiB before filesystem, Ollama installation, temporary space or other models. This is not a RAM/VRAM requirement. Only manifest metadata was fetched; its SHA-256 matches the full digest above. |
| Ollama v0.17.0 | Inspected ChatHandler does not implement explicit source routing; excluded by the new floor. No retry with an unsuffixed model is allowed. |
| Ollama v0.18.0, v0.24.0, v0.40.6 | Source inspection of `internal/modelref/modelref.go` and `server/routes.go` confirms the final `:local` is stripped to base `qwen3:4b-instruct`, while preserving local-source intent. ChatHandler refuses remote-configured models before remote dispatch. This is source compatibility evidence, not installed-model execution on Windows. |

Versioned primary source examples:
[v0.18.0 parser](https://github.com/ollama/ollama/blob/v0.18.0/internal/modelref/modelref.go),
[v0.18.0 request handler](https://github.com/ollama/ollama/blob/v0.18.0/server/routes.go),
[v0.24.0 parser](https://github.com/ollama/ollama/blob/v0.24.0/internal/modelref/modelref.go),
[v0.24.0 request handler](https://github.com/ollama/ollama/blob/v0.24.0/server/routes.go),
[v0.40.6 parser](https://github.com/ollama/ollama/blob/v0.40.6/internal/modelref/modelref.go),
[v0.40.6 request handler](https://github.com/ollama/ollama/blob/v0.40.6/server/routes.go).

### Safety and integration inspection

| Boundary | Finding and limit |
| --- | --- |
| Consent | Flutter requires the per-screen acknowledgement plus an explicit Start; native method has no text/model/URL arguments. No setting enables the local adapter by default. Resume preserves only the previously chosen session mode. |
| Safe Mode/recovery/foreground | Flutter clears acknowledgement and requests a latched block. Native owner independently refuses background/blocked starts and tears down requests on hide/deactivation/destruction. Re-entry does not restart inference. Microphone and cloud approval paths are unchanged. |
| Authentication | Native generates a fresh 32-byte random session credential, passes it only in the restricted child's environment, and owns revocation/termination. The sidecar enforces bearer auth, rejects Origin/non-loopback peers and bounds clients. The IPC credential is never forwarded to Ollama (regression assertions added). The operator's local Ollama HTTP service itself is unauthenticated; this is not daemon attestation. |
| Network/fallback | Fixed numeric loopback endpoint, proxies and redirects disabled, explicit-local show/chat, no pull or alternative/cloud retry. Tests reject unavailable/wrong/remote models before chat. For device acceptance, independently verify Ollama cloud is disabled and observe no outbound inference traffic; Neura cannot configure an already running user-owned daemon by setting its own environment. |
| Resource/cancellation | 2048 context, 192 predicted tokens, two requested threads; 4 KiB lines/frames, 3,000 output bytes, 64 KiB response, bounded queue and one local run per sidecar. HTTP futures are aborted on cancel/revoke and late results are discarded. Physical runner stop, memory release and contention across clients remain unmeasured. |

The six workflows attached to the **original** head were independently
confirmed successful: [coverage](https://github.com/Vantiger-Construction/neura_os/actions/runs/39202327533),
[offline text](https://github.com/Vantiger-Construction/neura_os/actions/runs/39202327522),
[Ollama](https://github.com/Vantiger-Construction/neura_os/actions/runs/39202327591),
[State Matrix](https://github.com/Vantiger-Construction/neura_os/actions/runs/39202327523),
[Windows Local Runner](https://github.com/Vantiger-Construction/neura_os/actions/runs/39202327631),
[Android packaging](https://github.com/Vantiger-Construction/neura_os/actions/runs/39202327526).
They do not validate the review changes or real-model Windows execution.

Review regressions first reproduced acceptance of an unsupported daemon and a
retargeted tag on the original code. New tests cover rejection before fixture
submission, official bare-hex/prefixed digest representations, independent
pin literals, stable/prerelease versions, credential isolation, and refusal to
count failed follow-up inference as cancellation recovery.

Local review validation: `cargo test --locked` passed **104 tests** (42 library,
31 sidecar, 6 evidence-tool, 2 evidence integration, 23 native lifecycle).
Rustfmt checks, `cargo clippy --locked --all-targets -- -D warnings`, and
`git diff --check` passed. Rust toolchain: 1.99.1, Linux x86_64. Flutter/Dart
SDK and a Windows runtime were unavailable here, so Flutter tests/analyzer and
native Windows compilation were not rerun locally. Fresh CI must cover the
changed head; the older six green runs above are not substituted for it.

### Device acceptance record still required

| Check | Required evidence; no result claimed here |
| --- | --- |
| Exact installation | Windows edition/build, CPU, GPU/VRAM, RAM, Ollama client and daemon versions, exact PR build SHA, installed tag/digest/size. Verify loopback listener and cloud-disabled daemon configuration; disconnect external networking for the local inference trial. |
| Real execution | With already installed reviewed weights, explicitly run Console local check. Capture non-content completion status and timings; confirm the exact `:local` identifier works on that installation. Test model missing, mismatched and daemon unavailable without pulling anything or enabling fallback. |
| Cold startup | On mains and battery, prove the model is absent from `/api/ps` before each trial, record TTFT and total. Verify the complete Console probe remains within 75 seconds, **and load plus generation fits the inner 60-second deadline**. Timeout must pause without retry or late Idle. |
| Memory | Record combined Neura/sidecar/Ollama/runner peak working set, VRAM, paging and UI responsiveness, plus the sampled system-memory delta. Include a near-admission-limit device; the estimate and permit are not a global daemon memory limit. |
| Cancel/safety | Test Stop, Pause, background/close, Safe Mode and recovery during cold loading and streaming. Record request/sidecar teardown, absence of late completion, runner compute cessation and unload separately. Follow-up-output timing includes another inference; it is not exact admission latency. |
| Owner decision | Approve model footprint/license and explicitly accept or strengthen the trusted-daemon/non-atomic-tag limitation. Then review fresh checks on the changed PR head. No merge or public-distribution approval is implied. |
