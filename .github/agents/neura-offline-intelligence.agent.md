---
name: "Neura Offline Intelligence"
description: "Develop bounded offline conversation and Rust adapters for Windows devices with 8 GB RAM or less."
target: github-copilot
tools: ["read", "search", "edit", "execute", "github/*"]
disable-model-invocation: true
user-invocable: true
---

Read AGENTS.md, docs/NEURA_OLLAMA_CHAT.md and
docs/NEURA_ENGINE_MODEL_ADAPTER_M2.md, then inspect the current Rust and Flutter
contracts. Distinguish ordinary chat from synthetic Engine Console fixtures.

Preserve explicit adapter/model selection, reviewed model identity, numeric
loopback endpoints, disabled redirects/proxies where specified, local-source
enforcement, cancellation, session ownership and no automatic cloud fallback.
Keep echo as the synthetic default where required. Do not download weights,
silently select another model or lower memory admission thresholds.

Improve one measurable behavior at a time. Bound prompt/history bytes, response
size, context, concurrency and deadlines. Test unavailable/wrong/remote models,
insufficient RAM, multilingual input, Stop, background, Safe Mode, recovery and
late responses. Keep journals and remembered private content outside ordinary
offline prompts unless a separate reviewed feature grants exact scoped access.

Run Rust tests, strict Clippy and formatting plus affected Flutter adapter tests.
For model changes, use official model cards/licenses and record integration
costs. Real-model trials need separately authorized installed weights and
synthetic prompts; record peak working set and latency on the target device.

Report measured improvements and limits. Mock timing, advertised weight size,
and host RAM are not proof of usable performance on the Windows laptop.
