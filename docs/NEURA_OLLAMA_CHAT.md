# Neura's Windows Ollama conversation

This change connects the existing Windows chat screen to an operator-installed
Ollama daemon through Neura's packaged Rust library. It does not install or train
a model, modify the synthetic Engine Console protocol, or enable background AI.
Use an updated Windows build from this branch after review and validation; an
older installed Neura build will not show this option.

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

## Boundaries

- Only `http://127.0.0.1:11434/api/show` and `/api/chat` are used. Rust disables
  HTTP proxies and redirects. No model download, authentication, cloud fallback,
  browser, web search or tool execution is implemented in this adapter.
- The model is fixed to `qwen3:4b-instruct`. A metadata preflight rejects remote
  model tags and non-Qwen3/4.0B/Q4_K_M models before conversation submission.
  Inference uses Ollama's explicit `:local` source suffix to reject remote
  aliases at execution time. Older daemons lacking this syntax must be updated;
  this adapter does not fall back to an unspecified model source.
  The separately installed daemon and its model files must be trusted. Metadata
  checks are not cryptographic model verification or an OS security sandbox.
- Files, images, recalled personal memories and earlier private-source replies
  are rejected. Start a fresh chat if previous turns used such sources. Ollama
  turns are not automatically written to Neura's long-term memory. Stored mood
  is excluded from the model prompt; local safety screening may still use it.
- Input and reply guardrails remain in the main chat path. Prompt rules do not
  prove clinical suitability; no diagnosis or medication advice is intended.
- Retention is at most eight recent turns and 1,500 UTF-8 content bytes, trimming
  whole older turns. Oversized newest messages or system instructions fail
  closed. The complete system prompt is preserved in Neura's request.
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

Official references:
- https://docs.ollama.com/api/chat
- https://docs.ollama.com/faq#how-do-i-disable-ollama-cloud-features
- https://ollama.com/library/qwen3:4b-instruct
