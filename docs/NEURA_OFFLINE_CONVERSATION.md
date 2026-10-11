# Offline text conversation on a small Windows laptop

This opt-in developer prototype connects Neura's Rust crate to a free local
language model. It is a separate terminal conversation, **not yet the Flutter
chat provider**. It does not start with Neura, replace the synthetic Engine
Console, or send a failed local request to a cloud provider.

Qwen3.5-2B and 0.8B are Apache-2.0 models by Qwen. The GGUF files below are
community quantizations published by Unsloth. llama.cpp is MIT licensed.
These small models can support casual conversation but will make mistakes;
naturalness, speed and peak memory still need measurement on the actual laptop.
Weight file size is not total runtime RAM usage.

## Memory selection

Run `tools/Start-NeuraLocalConversation.ps1 -PreflightOnly` in a foreground,
64-bit Windows PowerShell terminal. This reads actual total and free physical
memory without starting a model or downloading anything.

| Admission threshold | Selected model | Weight file size |
| --- | --- | --- |
| At least 7 GiB total and 3 GiB currently free | Qwen3.5-2B Q4_K_M | About 1.28 GB |
| At least 3 GiB total and 1.75 GiB currently free | Qwen3.5-0.8B Q4_K_M | About 533 MB |
| Below those thresholds, or unknown memory | Startup blocked | Close other apps and check again |

These conservative thresholds are estimates, not a guarantee against memory
pressure. Both profiles use CPU inference, two compute threads, one concurrent
turn, 2,048 context tokens, a 256-token reply cap and small processing batches.
The adapter counts actual template tokens and removes whole older turns when
needed. It retains at most four completed turns and 8 KiB of conversation text
in Rust. Messages over 2 KiB are rejected. There is no automatic summarizer.

## One-time setup while online

1. Download the official [llama.cpp b11429 CPU x64 archive](https://github.com/ggml-org/llama.cpp/releases/download/b11429/llama-b11429-bin-win-cpu-x64.zip).
   Its SHA-256 is `1283323272b04cd07905816a597a0da810918102de958f4ff6f7bbaa70ed2efe`.
   The launcher checks the complete archive before extracting it into a temporary
   runtime directory, so its executable and DLLs come from the same reviewed asset.
2. Download the model selected by preflight into a local `models` directory:
   [2B Q4_K_M](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/802854bfd388ed92748de119df31327962811548/Qwen3.5-2B-Q4_K_M.gguf),
   or [0.8B Q4_K_M](https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/ed4bdcdbcce9f095bb49e8759176c64e45fa294b/Qwen3.5-0.8B-Q4_K_M.gguf).
   These URLs pin revisions. Download both only if you want both memory profiles.
   The launcher checks the model against the SHA-256 in the table below.
3. Build the Rust terminal executable from the reviewed branch. Windows needs
   Rust's MSVC toolchain and C++ build tools. Dependency provisioning requires
   network access once; ordinary conversation after setup does not.

```powershell
cargo build --manifest-path rust/Cargo.toml --locked --release --bin neura_local_chat
```

| File | SHA-256 |
| --- | --- |
| Qwen3.5-2B-Q4_K_M.gguf | `aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223` |
| Qwen3.5-0.8B-Q4_K_M.gguf | `bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517` |

Retain the upstream licenses and notices if redistributing model/runtime assets.
The repository does not bundle or automatically fetch these large assets.

## Start a conversation offline

Disconnect the internet and run, from the repository root:

```powershell
.\tools\Start-NeuraLocalConversation.ps1 `
  -LlamaArchivePath 'C:\NeuraModels\llama-b11429-bin-win-cpu-x64.zip' `
  -ModelsDirectory 'C:\NeuraModels\models' `
  -AllowSessionText
```

The permission covers only text typed in that terminal during this invocation.
Startup clears inherited child environments, uses a fresh random local
credential, disables model downloads, Web UI, agent tools and prompt caching,
and verifies that the listening socket belongs to the launched server.
HTTP uses the literal `127.0.0.1`, with proxies and redirects disabled. The token
never appears in command-line arguments. Prompt logging is disabled.

Use `/quit`, `/stop`, or `/clear` to end the session. Any input while a reply is
being generated stops the session. Moving the terminal out of the foreground
also ends it; returning does not restart it. The launcher closes its Windows
job, terminates/reaps the children, and removes the temporary runtime files.
There is no retry or conversation replay. Model files remain for later use.

## Boundary with the Companion OS

The prototype never opens Neura's journal, encrypted memory, approved-source
leases, microphone, TTS, cloud swarm, action dispatcher, or settings. It does
not alter Safe Mode, consent controls, encrypted-memory storage, offline ASR,
update policy, or release publication workflows. Its terminal output is
session text, and the terminal's own scrollback may retain it. Zeroizing Rust
buffers is best-effort cleanup, not protection against OS paging or crash dumps.

This standalone harness does not observe the Flutter application's Safe Mode
or recovery signals. Before using the adapter inside the app, a native session
owner must revoke the text grant and terminate its model process on Safe Mode,
recovery, pause, backgrounding, screen disposal and host shutdown. Publication
must also reject replies from superseded sessions. Do not expose the constructor
as an unrestricted user-supplied URL or add an automatic cloud fallback.

Future memory access must use existing scoped consent and encrypted storage.
Future voice integration must keep microphone capture, local ASR and TTS behind
their existing controls. Generated text must never authorize or dispatch actions.

## Validation before app integration or release

CI runs all Rust targets and strict Clippy on Linux and Windows, plus Windows
memory-policy, asset-verification, argument-quoting, launcher syntax and owned-child
termination checks. The local HTTP fixtures test bounds, token budgeting,
revocation during generation, tool-output rejection and redirect refusal.
No model download or actual inference is part of these unit checks.

Before approving this prototype, run the pinned binary and both selected model
profiles on the laptop without internet. Record peak working set, first-reply
latency, reply quality and shutdown behavior (stop, focus loss, Ctrl+C and shell
closure). Check that no listener or child remains and that no prompt files were
created. Verify `/apply-template` and `/tokenize` agree with the generation
template, including the disabled-thinking configuration. Windows job attachment
happens immediately after process creation; the native in-app owner should use
suspended creation and assignment before resuming, as the synthetic owner does.

This work is stacked on the rustls fix in draft PR #121. Review that security
change separately, then retarget this draft to `Neura` after it is merged and
rerun checks against the resulting head. Neither PR is merged automatically.

Sources: [Qwen 2B model card](https://huggingface.co/Qwen/Qwen3.5-2B),
[Qwen 0.8B model card](https://huggingface.co/Qwen/Qwen3.5-0.8B),
[Unsloth weight metadata](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/blob/main/Qwen3.5-2B-Q4_K_M.gguf),
[llama.cpp v0.6.0 server documentation](https://github.com/ggml-org/llama.cpp/blob/v0.6.0/tools/server/README.md),
[official runtime assets](https://github.com/ggml-org/llama.cpp/releases/tag/b11429).
