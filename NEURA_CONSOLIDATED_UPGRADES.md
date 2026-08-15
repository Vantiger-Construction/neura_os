# Neura consolidated upgrades

This source tree combines the upgrades available in the August 2026 recovery
workspace while preserving Neura's existing wellness, memory, voice, avatar,
money, goals, clinical-support, notifications, Legacy, and Swarm modules.

## Neura 1.3 Intelligence Fabric

- A local Signal Graph fuses numeric mood history, quest momentum,
  user-authored goals, and Focus Mode with confidence, freshness, sensitivity,
  and bounded evidence. Raw journals, therapy, dream, mood-note, and memory
  text are not read.
- Deterministic Opportunity Radar specialists propose gentle resets, smaller
  quest steps, goal-to-quest drafts, and focus support without side effects.
- The Autonomy Kernel applies Safe Mode, quiet hours, Focus Mode, cooldown,
  daily-limit, recent-decline, privacy, capability-risk, and approval policy.
- Explainable Decision Receipts and the Intelligence Center expose attention,
  sensitive-signal, capability, consent, and history controls.
- Dashboard cards show “Why?” and commit quota only after rendering. Opening a
  card never silently performs its action.

## Durable, scoped consent

- The Action Loom Approval Broker binds authority to an exact candidate,
  policy receipt, evidence set, and payload; it revalidates immediately before
  execution and rejects expired, changed, blocked, or ambiguous actions.
- Submission, execution, and undo are idempotent under concurrent calls.
  Sensitive and external effects require fresh approval; critical effects are
  blocked from autonomous execution.
- The first executor turns an approved goal into one deterministic local quest.
  A cryptographic fingerprint and durable execution state provide crash
  recovery and cross-restart duplicate prevention. Undo is refused after quest
  progress exists.
- Bounded consent and execution ledgers contain operational metadata only:
  identifiers, status, approval state, timestamps, quest ID, and a one-way
  fingerprint. Raw goals, recommendation copy, journals, and notes stay out.

## Cloud-tool privacy

- Model-requested mood-history access, mood-check-in saving, room navigation,
  and tone changes require a concrete confirmation for that request.
- A confirmed mood-history share contains only dates and numeric scores.
  Existing mood notes are never exported through the tool loop, and a save
  result does not echo note text to the provider.
- Room policy is checked again at execution time. Declines remain declines and
  do not grant later authority.
- Ephemeral chat logs retain character counts instead of raw response content.

## Encryption, credentials, and complete wipe

- Memory data remains AES-GCM encrypted with a random key in OS secure storage.
  New key creation is accepted only after verification; migration keeps a
  legacy key authoritative until its matching secure copy is verified and
  committed. Missing expected keys fail closed rather than being replaced.
- Anthropic credentials use verified OS secure storage. A migration tombstone
  prevents a cleared key from reappearing from a legacy build-time value.
- Full local-data removal now has fail-closed transactional completion
  semantics. It latches Safe Mode, cancels active generation, stops or drains
  microphone, notification, intelligence, memory, timeline, logging, and
  native writers, then clears caches, credentials, keys, preferences, and exact
  app-owned document, support, recording, and temporary paths.
- Every deletion category is attempted and aggregate failures are surfaced.
  If any step fails, affected writers and keys stay suspended so late work
  cannot recreate deleted data. Regenerable stores resume only after complete
  success; Safe Mode and native/provider credential access stay latched until
  restart.

## Safe Mode and platform hardening

- Safe Mode is enforced at startup and inside cloud AI, native Swarm, ambient
  capture, wake-word, TTS, notification, proactive-card, and shell boundaries.
  A direct service call cannot bypass the gate.
- Clearing Safe Mode writes a clean next-launch state but deliberately keeps
  the current process latched. Diagnostics exposes the required restart.
- A Safe Boot state failure starts fail-closed, while optional module failures
  remain visible through startup health and Timeline Vault.
- Desktop window-manager initialization is limited to supported platforms:
  Windows retains the secondary mascot role, macOS primary startup is
  best-effort, and mobile/web skip that path.
- The native Rust Swarm is packaged for Windows only; web receives a safe
  fallback. macOS includes the secure-storage keychain access group.
- The After Storm ↔ Weekly Snapshot recursion path is removed.

## Neura 1.2 foundations retained

- Secure provider settings, room-scoped model policy, SSE streaming,
  cancellation and barge-in, bounded retry/backoff, local fallback, tone and
  dispatch hooks, and diagnostics remedies.
- Neura Link v1 typed WebSocket protocol, optional sidecar lifecycle with a
  crash-loop guard, and the Rust `neura_api` loopback service on
  `127.0.0.1:8787`.
- Append-only Timeline Vault, live Module Health, crash-loop-aware Safe Boot,
  and Diagnostics recovery controls.

## Run and release

For local-brain protocol testing, run `RUN_NEURA_LOCAL_BRAIN.bat`, then
`RUN_NEURA_LOCAL.bat`, and use Settings > Local Brain Console. The local-brain
executable uses a safe echo adapter; Neura's primary chat remains on its secure
provider path.

The GitHub recovery workflow derives Windows and Android artifact names and
versions from `pubspec.yaml`. It installs Flutter, restores dependencies,
records a formatting patch, runs analysis and Flutter tests, and builds
recovery artifacts only after verification. Verification artifacts retain the
logs and generated `pubspec.lock` when available.

Flutter, Dart, Rust, and Windows PowerShell are not installed in the packaging
environment used for this consolidation. Tests are installed but were not run
here, and no build success is claimed. Before release:

1. Run the GitHub workflow for the release branch.
2. Run `BUILD_ALL_NEURA_UPGRADES.bat` on a configured Windows build host.
3. Resolve every analyzer, test, format, Rust, or build failure.
4. Revoke any provider key ever distributed inside a ZIP or executable, and
   never release with `--dart-define=ANTHROPIC_API_KEY=...`.
