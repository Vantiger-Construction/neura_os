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
75-second probe deadline (the sidecar's 60-second run deadline plus loading)
and up to 200 response frames (192 predicted tokens, each possibly its own
delta, plus the completion). Exhausting either pauses the session, as in the
echo check. A run-time `error` with an unavailable code maps to
`model_unavailable`; a budget or timeout error maps to exhaustion; any other
error is a failure.

Native status slot 8 is `model_unavailable`. Flutter shows it with what the
operator needs to do (start Ollama and install the pinned model) and treats it
like `unavailable`: the session is stopped and a new explicit start is
required.

## The pinned model

`rust/src/local_model.rs` is now the single contract shared by the Windows chat
adapter (#127) and the sidecar:

- Tag `qwen3:4b-instruct`, requested as `qwen3:4b-instruct:local` so Ollama
  rejects remote aliases at execution time.
- Metadata must report family `qwen3`, parameter size `4.0B`, quantization
  `Q4_K_M`, and no `remote_host`/`remote_model`.
- Fixed endpoint `http://127.0.0.1:11434`, no proxy, no redirects, 2-second
  connect deadline. `LoopbackClient` is the only way the module reaches a
  daemon and accepts only numeric loopback `http://` endpoints, so neither
  verification nor chat can be pointed at a LAN, public or DNS host.
- Windows admission budget: at least 7 GiB installed and 3.5 GiB available
  memory. Other platforms are not admitted.

Neura never installs, downloads, pulls, starts or stops a model or the daemon.
Installing Ollama and the pinned model is the operator's explicit choice.
There is no echo, alternative-model or cloud fallback once `ollama-local` is
selected: an unverifiable model is reported as unavailable and refuses work.

## Diagnostics

`diagnostics` keeps its v1 shape and adds `model_mode`:

| `model_mode` | Model adapter check | Meaning |
| --- | --- | --- |
| `echo` | `degraded` | Default echo provider (unchanged text). |
| `local` | `ok` | Admission passed and the pinned model verified just now. |
| `unavailable` | `unavailable` + `code` | Opted in, but the model cannot be used. |

Unavailable codes: `unreachable`, `not_installed`, `remote_model`,
`model_mismatch`, `malformed_metadata`, `insufficient_memory`. They never
include daemon output.

For the local adapter, diagnostics also report the pinned `model` identity and
a content-free `last_run` record: fixture name, outcome (`completed`,
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
which drops the HTTP response and closes the connection to Ollama, so the
daemon abandons generation. The run is recorded as `cancelled` with the
TTFT and output size observed so far; the record is created before the task is
spawned, so even a run aborted before it starts is recorded. No late completion
is delivered or replayed.

## Validation

```text
cargo test --manifest-path rust/Cargo.toml --locked --bin neura_api
cargo test --manifest-path rust/Cargo.toml --locked --test engine_session_lifecycle
flutter test test/neura_link/engine_session_lifecycle_test.dart
cargo test --manifest-path rust/Cargo.toml --locked --lib local_model ollama_conversation
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
| `cancellation` | Cancel at the first streamed delta: time until the connection closed, the recorded outcome, and time until the adapter accepted new work. |

The sidecar requests the model with `keep_alive: 0`, so every run is a cold
load; the timings are the ones an operator sees. The tool refuses to start
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
