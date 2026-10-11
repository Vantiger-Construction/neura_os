# Windows offline text chat preview

This draft connects Neura's main Flutter chat screen to the local Rust adapter
from PR #123. It is off by default, Windows-only, and uses only newly typed
session text. It is not a release-ready mental-health model or a measured
performance improvement. Real inference on the laptop remains a review gate.

## Explicit setup and choice

Use the exact runtime archive and model revisions/checksums in
[the prototype guide](NEURA_OFFLINE_CONVERSATION.md). Download them manually
while online; neither build nor app downloads inference assets. Place the
reviewed files in this fixed operator-managed layout:

```text
%LOCALAPPDATA%\Neura\offline-text\
  llama-b11429-bin-win-cpu-x64.zip
  models\Qwen3.5-0.8B-Q4_K_M.gguf
  models\Qwen3.5-2B-Q4_K_M.gguf
```

Only the profile admitted by actual total/free memory is required. The native
launcher selects and verifies it each time. A missing model, bad checksum,
unknown/insufficient memory, denied script execution, or missing native support
fails closed. The laptop's stated RAM alone does not establish admission.

Build from the reviewed stack with the normal Windows MSVC/Rust tools:

```powershell
flutter pub get --enforce-lockfile
flutter build windows --release --dart-define=NEURA_ENABLE_OFFLINE_TEXT=true
```

The Windows build includes the Rust library and three small launcher support
files next to the executable under `offline-text`. It does not bundle weights
or llama.cpp. Keep that subdirectory when copying the built app. The existing
Windows PowerShell execution policy must allow those reviewed local scripts;
the native launch does not change policy or supply a bypass switch.

Open Chat options → Offline text chat (preview), then choose Start offline chat.
This clears a previous draft and starts a separate transcript. Wait for `idle`
before sending. The prior standard-chat history is never supplied to the local
engine. The local persona is the adapter's fixed Neura persona; the standard
agent/mode choices do not change this preview.

Stop ends the complete session. A new Start requires a fresh explicit choice.
Errors, failed starts and backgrounding keep offline selected; they do not send
the message to another provider. Choosing Use standard chat is a separate user
choice and resumes the existing chat path with its fresh cloud-approval gates.
Offline turns are never replayed into that path.

## Ownership and lifecycle

Flutter sends only argument-free Start/Stop/Block/Poll controls and one bounded
UTF-8 text string per turn. No URL, credential, model, executable, source lease,
tool definition or action argument crosses this channel. It is registered only
on the primary Windows engine. Other platforms/builds do not offer the option.

The Rust native owner creates a fresh credential and a cleared-environment
Windows PowerShell child through the existing process owner. Creation is
suspended, assignment to a kill-on-close job precedes ResumeThread, and the
launcher/server descendants inherit that outer job from birth. The reviewed
launcher verifies pinned assets, observes the actual app HWND, verifies socket
ownership, and reports one bounded literal-loopback readiness receipt. Rust
then performs local HTTP directly, with proxies/redirects disabled and tracing
suppressed. Text does not pass through PowerShell output, arguments, or files.

Stop, pause through Stop, background/inactive/hidden/detached states, minimization,
focus loss, power suspend, Safe Mode, recovery, screen disposal, host closure and
host process death end ownership. Foreground return never starts a model.
Safe Mode/recovery latch the running native host against new local grants;
restart normally after resolving those states. Revocation invalidates result
epochs before cancellation, joins the worker/pipe reader and terminates/reaps
owned children. Temporary extracted runtime files are removed on normal
teardown. Abrupt host death can leave extracted binaries to clean up, but no
prompt files are intentionally created.

Flutter also invalidates pending replies immediately, skips revoked queued
submissions, serializes data/control polling and requires confirmed Stop before
replacement grants. Safety teardown is sent immediately even if a poll reply is
delayed. A failed teardown blocks further local grants in that view.

## Bounds and source restrictions

The original memory profiles remain unchanged: 2B requires at least 7 GiB total
and 3 GiB free; 0.8B requires at least 3 GiB total and 1.75 GiB free. These are
admission estimates, not measured peak-memory guarantees. CPU inference uses
two compute threads, one concurrent turn, 2,048 context tokens, 256 reply tokens
and small batches. Actual rendered-template token counts govern trimming.

Accepted messages are at most 2 KiB UTF-8, replies at most 4 KiB, and HTTP response
bodies at most 64 KiB. Rust retains at most four completed turns and 8 KiB of
text. Flutter separately retains at most eight visible messages and 8 KiB,
removing whole older turns. The one-item input channel is an ownership handoff;
no second turn is admitted while working or while a reply awaits consumption.
Startup and generation have bounded deadlines and no automatic retries.

No journal, mood history, encrypted-memory adapter, approved-source lease,
microphone, TTS, image, cloud router, automatic summarizer or action dispatcher
is called for these turns. There are no chat-memory writes or prompt logs.
The existing explicit-crisis text scan routes matching typed messages to the
reviewed static support resources/playbooks without inference or storm-event
persistence. This limited routing floor is not comprehensive safety assessment.
The manual guided-support screen remains available and stops local ownership
before navigation.

Ending the session removes its visible transcript and drops Rust/Dart references.
Rust zeroization is best effort; Dart strings, GC copies, OS paging, screenshots
and crash dumps are not secure erasure. A Windows job supplies process ownership,
not a security sandbox. Personal sources remain outside this preview.

## Validation and remaining device gate

The dedicated workflow targets this stack as well as the original bases. It
runs locked Rust tests/strict Clippy on Linux and Windows, Windows asset-policy
and launcher checks, Flutter analysis and the full suite on both platforms, and
compiles the native channel owner against genuine Flutter Windows headers.
Fixtures exercise input/response/context bounds, native revocation, stale
results, one-turn admission, process reaping, Windows descendant termination,
foreground/safety/recovery/disposal behavior and local UI routing. Fixture
success is not real model inference, clinical validation or a complete Windows
app/package smoke test.

Before approval, build and run the full Windows app on the laptop while offline.
Record results for each admitted profile rather than assuming both fit:

| Check | Required observation |
| --- | --- |
| Admission | Actual total/available RAM with the Flutter app already open; selected profile |
| Cold start | Time from explicit Start to idle; peak combined working set of app, PowerShell and llama.cpp |
| Conversation | Several everyday tasks, follow-ups, correction handling, uncertainty and context trimming; record failures as well as successes |
| Latency | Submit-to-visible-reply latency for short and longer accepted messages; this preview is non-streaming |
| Memory | Peak combined working set and system available RAM during several turns; watch for paging or UI freezes |
| Template | Pinned runtime `/apply-template` and `/tokenize` match disabled-thinking generation configuration |
| Cancellation | Stop during checksum/extraction/loading/generation; no late bubble, listener or remaining owned child |
| Lifecycle | Focus loss, minimize, suspend, screen close, app close/forced termination, Safe Mode and recovery; explicit restart only |
| Privacy | No transcript/prompt files or text logs; attachments, memories, voice and TTS disabled; no outbound inference connections |
| Routing | Missing/corrupt assets and local errors keep offline selected; standard/cloud routing needs a deliberate switch and fresh approval |
| Packaging | Full Windows build/launch with support files present; normal builds hide the option; Android remains unsupported |

This work is stacked on PR #123, which is stacked on the open TLS security fix
PR #121. It preserves that parent's rustls 0.23.45/rustls-webpki 0.103.15 lockfile
without new dependency versions. Review each layer separately. After parents
land, retarget and rerun checks against the resulting heads. No merge or release
is performed automatically.
