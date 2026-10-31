# Neura Companion OS — October companion upgrades

Review branch based on `Neura` commit `29ffea432b2fe09dea9012858b4d3e9f7214ccfe`,
with draft memory PR #141 (`fe212c73ec5da85f77356bfdd702466611d595f7`)
integrated into this branch. Neither integration nor a push approves release.

## Changes and where to find them

| Upgrade | User entry point | Implementation and limits |
| --- | --- | --- |
| Offline conversation continuity | Neura chat, Offline Ollama, conversation mode menu | Bounded recent context starts on a user turn and preserves the newest message without truncation. Balanced and Companion instructions discourage repeating answered questions. Model weights, tools, model identity and cloud approval are unchanged. Actual response quality requires model/device evaluation. |
| Controlled encrypted memory | Existing companion-memory screen and next-reply memory control | Includes the full scoped-consent implementation from draft #141: author notes explicitly; separate permissions for review, remembering, prompt recall and clearing; no automatic raw-chat copy or legacy-history migration. Offline Ollama still excludes saved memories. See ENCRYPTED_MEMORY_RELEASE_CONTRACTS.md. |
| Visible activity | Chat status chip and existing room avatar | Actual request-scoped thinking leases, local speech/listening leases, Safe Mode priority, offline and background labels. Avatar motion controllers stop on reduced motion, inactive lifecycle or disabled tickers. No sensor or model is activated to animate an avatar. |
| Startup recovery | Critical startup failure controls | Retry, explicitly latch Safe Mode before retrying, preview a content-free summary and copy it on request. Recovery layout scrolls on short displays. Cannot display UI after native process termination or diagnose the Samsung failure without device evidence. |
| Daily planning | Command palette: Plan my day; chat options: Plan my day | One goal, an optional local starter checklist, editable steps, preview, explicit approval and manual completion. Editing invalidates approval and progress. This is a session-only checklist, not an LLM planner or action executor. Clears on background, Safe Mode and screen disposal; never writes plaintext plans to preferences or sends them to a provider. |
| Bounded offline controls | Chat options: Offline conversation controls (after selecting Offline Ollama) | Compact: 750 UTF-8 bytes of recent turns; Standard: 1500. Fixed Qwen3 4B remains selected. Explicit RAM check reads two numeric Windows OS counters without loading the Rust DLL or contacting Ollama. Discards stale results on background. Existing Rust admission independently checks 7 GiB installed / 3.5 GiB available before every request. Compact context does not make the model fit below this floor. |

## Safety and privacy

No automatic model download, cloud fallback, background inference, new network
endpoint, automatic action execution, automatic journal import, or new telemetry.
The RAM snapshot has no device identity, paths or conversation text. Startup
summary export permits only a fixed version, allowlisted module, Safe Mode bit
and incomplete-startup bit. Existing local journaling remains authoritative.

The new planner does not persist across restarts. Its approval authorizes only
checking off items manually; it grants no authority to Action Loom or an LLM.

## Local verification

On the combined source, Flutter 3.47.5 completed **954 Flutter tests** with
`--no-pub --concurrency 2 --timeout 2m`; all passed. The **18 focused upgrade
tests** also passed independently. Targeted Flutter static analysis reports no
issues; canonical Dart formatting reports 20 files with zero changes.
The existing security-helper suite passed **10 tests**. The Windows plugin-filter
CMake suite passed **3 tests** after installing its initially missing CMake
test dependency in scratch. Locked Dart/Rust
lockfiles were unchanged, workflow YAML/test wiring parsed successfully, and
`git diff --check` passed.

Flutter's first setup attempt was blocked by automatic review for the SDK's
Azure metadata detection. Inspecting its source identified the supported
`CI=true` short-circuit; subsequent validation used it with analytics disabled,
so no metadata access was needed. Archive extraction used `--no-same-owner`
because this environment cannot restore upstream archive ownership.

Synthetic widget tests are not physical Windows/Samsung acceptance or evidence
of conversational quality. Native Windows compilation and Rust validation are
left to the existing hosted workflows; neither was run locally.
The Ollama workflow now analyzes and tests the new integrations; the existing
full coverage, encrypted-memory, safety and Windows build gates remain required.
No protections, audit findings, coverage thresholds or failures are suppressed.

## Device acceptance before release

- Windows: compile/package the actual branch; select Offline Ollama, verify
  Standard/Compact handling, wrong-model rejection, low-memory rejection,
  cancellation, background clearing and no cloud fallback. RAM readiness is
  momentary and does not attest Ollama/model readiness.
- Test conversation usefulness with the same installed pinned model and synthetic
  prompts before/after. Record unanswered/empty/failed replies, p50/p95 time,
  peak RAM and human-rated usefulness separately; do not infer improvement
  from prompt text or byte-budget tests.
- Verify encrypted native-store recall/revocation/wipe/restart behavior per the
  memory release contracts. Keep memory #141 draft until its review is complete.
- Samsung SM-S366V: obtain the installed APK identity and actual startup logs;
  confirm retry/recovery rendering on the device. This branch does not claim
  to fix an unobserved native crash.
- The pre-existing dependency audit reports Tokio 1.53.1 / RUSTSEC-2026-0386
  in #146's evidence. This branch does not establish exposure or remediation;
  retain the security gate and review fresh results before release.
