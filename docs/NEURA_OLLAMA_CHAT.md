# Neura's Windows Ollama conversation

This change connects the existing Windows chat screen to an operator-installed
Ollama daemon through Neura's packaged Rust library. It does not install or train
a model, modify the synthetic Engine Console protocol, or enable background AI.
Use an updated Windows build from this branch after review and validation; an
older installed Neura build will not show this option.

## Reviewable Windows preview

The **Neura Ollama Chat** workflow checks out the exact PR head for each job.
After Rust tests/strict Clippy and Flutter integration checks pass, its hosted
Windows job runs the complete Flutter test suite and the existing portable
Windows build script. `-SkipFormatting` prevents the build from rewriting
reviewed sources; canonical formatting is enforced by the preceding jobs.
The build also rejects changes to app/native/Rust sources or dependency locks.

The Actions artifact is named `neura-ollama-windows-<full head SHA>`. It contains
`Neura-Ollama-Preview-<12-character SHA>.zip`, `SHA256SUMS.txt`, and
`OLLAMA_PREVIEW_MANIFEST.json`. A successful job verifies both the packaged and
freshly extracted app's launch sentinel, the actual packaged Rust exports,
background/blocked native admission, payload completeness and binary hashes.
It does not run Ollama or establish that the installed UI can complete a model
conversation. A queued/failed job is not a preview delivery receipt.

To try a successfully verified artifact, download it from the workflow's
Artifacts section while signed in to GitHub. Expand the outer artifact ZIP,
then check the inner preview before extracting it:

```powershell
Get-FileHash .\Neura-Ollama-Preview-*.zip -Algorithm SHA256
```

Compare this value with the corresponding `SHA256SUMS.txt` line and the manifest.
Extract the inner ZIP into its own user-writable folder, keeping the complete
`app` directory together, and start `app\START_NEURA.bat`. Close an older Neura
instance first. This unsigned x64 portable preview does not replace the installed
app, install a model, or act as a production installer. Existing
local app-data paths may still be shared with an earlier build; export important
local data using the existing app controls before trying a draft. The bundled
VC runtime DLLs come from the runner's Visual Studio redistributable directory.

## Laptop setup

Install and open the current Ollama release, then run in PowerShell while online:

```powershell
ollama pull qwen3:4b-instruct
[Environment]::SetEnvironmentVariable('OLLAMA_NO_CLOUD', '1', 'User')
```

Quit Ollama from its tray icon and reopen it so the local-only setting takes
effect. Keep its default loopback listener; do not expose port 11434 on the LAN.
Do not run another model chat concurrently on an 8 GB machine. Close memory-heavy
apps. Rust admits requests only with at least 7 GiB total physical RAM and
3.5 GiB available; these are estimates, not a guarantee against memory pressure.
The download is about 2.5 GB and remains available for offline inference.

In Neura's main chat, select the computer/cloud menu in the top bar and choose
**Offline Ollama**. Send a short text such as “Help me make a manageable plan
for today.” The conversation uses Neura's charter, persona, room framing and
audience instructions. API keys are not required. Existing reply speech settings
still control the Windows system voice; voice recognition is not installed by
this change. This version returns the complete reply rather than token deltas.
While it is working, **Stop offline reply** cancels the current request and keeps
Offline Ollama selected.

## Boundaries

- Only `http://127.0.0.1:11434` endpoints `/api/version`, `/api/tags`,
  `/api/show` and `/api/chat` are used. Rust disables
  HTTP proxies and redirects. No model download, authentication, cloud fallback,
  browser, web search or tool execution is implemented in this adapter.
- The model is fixed to `qwen3:4b-instruct`. A preflight requires stable Ollama
  >=0.18.0 and the reviewed manifest digest in
  [the shared model contract](NEURA_ENGINE_MODEL_ADAPTER_M2.md#the-pinned-model), then rejects remote
  model tags and non-Qwen3/4.0B/Q4_K_M models before conversation submission.
  Inference uses Ollama's explicit `:local` source suffix to reject remote
  aliases at execution time. Older daemons lacking this syntax must be updated;
  this adapter does not fall back to an unspecified model source.
  The separately installed daemon and its model files must be trusted. Metadata
  checks are not cryptographic model verification or an OS security sandbox.
- Ordinary chat rejects files, images, recalled personal memories and earlier
  private-source replies. The separate **Offline reference shelf** can send only
  displayed passages for one explicitly approved local answer; see
  [the companion upgrade guide](COMPANION_NEXT_STAGE_2026_10.md). Start a fresh chat if previous turns used such sources. Ollama
  turns are not automatically written to Neura's long-term memory. Stored mood
  is excluded from the model prompt; local safety screening may still use it.
- Input and reply guardrails remain in the main chat path. Prompt rules do not
  prove clinical suitability; no diagnosis or medication advice is intended.
- Retention is at most eight recent turns and 1,500 UTF-8 content bytes, trimming
  whole older turns. Oversized newest messages or system instructions fail
  closed. The complete system prompt is preserved in Neura's request.
- The offline editor rejects pastes above 1,500 UTF-8 bytes before retention;
  submission independently checks this cap. Visible history drops whole oldest
  messages above eight messages or 16 KiB of text (plus the initial greeting).
  This display budget lets a bounded reply remain readable; it is separate from
  the smaller model-context budget. Selecting offline clears the current draft.
- Inference uses 2 CPU threads, 2,048 context tokens, 256 output tokens and a
  90-second deadline. Ollama tokenizes and may truncate to its context limit;
  byte limits are not exact token budgeting. Long/multilingual conversation
  quality and system-prompt retention require device validation.
- Barge-in, chat closure, backgrounding, window deactivation, Safe Mode and
  recovery invalidate the request and suppress stale results. Safety blocking
  is latched until app restart. The DLL owner joins its worker on destruction.
  Cancellation closes Neura's HTTP request; Neura does not kill the separately
  managed Ollama process or guarantee instantaneous backend compute cessation.
  `keep_alive: 0` requests model unloading after completion.
- Rust retains no conversation history between requests and deliberately writes
  no prompts/replies to disk or logs. Sensitive buffers are not all guaranteed
  to be erased from allocator memory. Ollama/Windows have their own diagnostics
  and retention behavior. No private journals are used as training data.

## Required validation before release

Run Rust tests and strict Clippy, Flutter adapter tests, canonical formatting,
the existing consent/lifecycle suites and the Windows package/launch checks on
the exact PR head. On the actual 8 GB laptop, verify text conversation with the
internet disconnected, unavailable/wrong model behavior, peak RAM and latency,
window focus loss, stop/barge-in, navigation, Safe Mode and recovery during a
reply. Test everyday planning, unsupported beliefs, dependency pressure and
crisis language with synthetic examples. Never use real private journals for
these trials. This is an integration candidate, not a validated clinical release.

## Remaining laptop evidence

An “8 GB or less” laptop is not automatically admitted: the current profile
needs 7 GiB physical RAM and 3.5 GiB currently available. A smaller machine or
one with hardware-reserved memory may fail this gate. Do not lower the gate or
silently select the separately developed llama.cpp profile to bypass it.
Check free disk on the model location and extraction location: the model alone
is about 2.5 GB, and the ZIP plus extracted app require additional space.
Flutter, Rust and Visual Studio are build prerequisites, not requirements for
running the complete portable package.

| Trial | Evidence to record using synthetic text |
| --- | --- |
| Installation and selection | Windows version/CPU, exact preview SHA and hash, Ollama version, `ollama list`, loopback-only listener, cloud-disabled configuration, and the Offline Ollama menu visible in this preview. |
| First and repeated reply | Disconnect internet after manual setup. Record submit-to-complete-visible milliseconds for five short turns; this adapter does not stream first-token deltas. Confirm Neura's identity, tone, room and audience framing. |
| Memory and unload | Record total/available RAM before admission and during replies; combined Neura/Ollama/runner peak working set, paging and responsiveness; use `ollama ps` to confirm unloading after completion. |
| Negative cases | Ollama closed, model missing/wrong/remote, incompatible daemon and insufficient available RAM: fixed local failure, offline remains selected, no cloud request or automatic download. |
| Cancellation | During a slow reply test Stop/barge-in, focus loss, minimize, suspend, chat closure/navigation, Safe Mode, recovery and app exit. No stale reply or automatic restart; Safe Mode keeps microphone off and latches until restart. Separately observe how quickly the user-owned daemon stops computing. |
| Privacy and support | No model access to selected sources/images/remembered personal context or automatic long-term chat-content writes. Existing local guardrails may read stored mood and save fixed support-event metadata; inspect those stores separately. Check offline bounds on ASCII/multibyte input and long sessions, and review uncertainty, unsupported beliefs, dependency pressure and crisis language with synthetic examples. |
| Deliberate cloud use | A manual switch back requires the existing fresh cloud-request preview/approval. Cancelling local inference never selects cloud. |

Do not report these trials as passed until measured on the actual laptop. Keep
prompt/reply contents out of performance receipts and diagnostics shared for
review. The Ollama model supplies the weights; Neura's reviewed charter supplies
her companion identity. This integration does not train a Neura-owned model.

## Branch reconciliation and the llama.cpp integration

This branch is refreshed with default commit
`426158631aa608e490098eff1675d7f3706cec5e`, which includes the merged #125 charter
and #124 coverage workflow. Both #125 charter/spec files were already
byte-for-byte identical here; only their ancestry needed reconciliation.

PR #126 merged as `1caf9e02241c4947cd3553f2ebe52b16033d3cfe` into PR #123's
`agent/neura-offline-text-low-memory-2026-10-11` branch, not `Neura`.
That stack remains distinct and includes the open #121 TLS dependency refresh.

| Area | Ollama #127 | llama.cpp #123 + #126 | Later reconciliation |
| --- | --- | --- | --- |
| Flutter chat | Explicit Offline Ollama selector using the existing AI-service charter/guardrails | Separate opt-in text-session UI behind `NEURA_ENABLE_OFFLINE_TEXT=true` | A three-way merge trial found six conflict sections in `lib/modules/chat/neura_chat_screen.dart` (imports, send path, status and source controls); keep deliberate provider selection and separate session lifetimes. |
| Rust modules | `ollama_conversation` with fixed loopback HTTP | Local conversation and owned-child session modules | Both add modules in `rust/src/lib.rs`; the three-way trial merges this file cleanly. Retain both if the second provider is deliberately adopted. |
| Windows owner | Existing primary `NeuraEngineSession`; user owns Ollama daemon | Dedicated `NeuraLocalConversation`; Neura owns suspended/job-assigned llama.cpp children | Preserve each teardown contract; do not apply child-kill behavior to user-owned Ollama. |
| Model/memory | Fixed Qwen3 4B; 7 GiB total / 3.5 GiB available | Pinned Qwen3.5 2B or 0.8B assets with lower RAM profiles | No automatic provider/model substitution, download or cloud fallback. |
| Native/build files | Existing DLL packaging rules remain in place | Adds runner sources, owner and CMake/native validation | Current #127 does not modify these overlapping runner files. Re-review the whole combined package if that stack later lands. |

No llama.cpp code or dependency changes are imported by this refresh. #127
remains a draft, with no automatic merge, release publication or laptop install.

Official references:
- https://docs.ollama.com/api/chat
- https://docs.ollama.com/faq#how-do-i-disable-ollama-cloud-features
- https://ollama.com/library/qwen3:4b-instruct
