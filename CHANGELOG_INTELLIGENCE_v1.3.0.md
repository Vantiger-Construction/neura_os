# Neura OS 1.3.0+5 — Intelligence Fabric

## Added

- A local-first Intelligence Fabric: Signal Graph, Opportunity Radar, Autonomy
  Kernel, Decision Receipts, Consent Ledger, Action Loom, and Intelligence
  Center.
- Freshness-aware fusion of local mood scores, quest momentum, goals, and
  Focus Mode. Missing signals are omitted instead of treated as negative.
- Deterministic, side-effect-free specialists for gentle resets, smaller quest
  steps, goal-to-quest drafts, and focus support.
- Explainable policy decisions covering Safe Mode, quiet hours, Focus Mode,
  cooldowns, daily caps, recent declines, sensitivity, capability risk, and
  required approval.
- Dashboard recommendations with a visible “Why?” explanation. A card does
  not perform its proposed action when opened.
- A narrow first Action Loom executor: review an exact goal-to-quest draft,
  approve it once, create it locally, and undo while no quest progress exists.

## Consent and durability

- Action submission, execution, and undo are idempotent, including concurrent
  calls. Candidate reuse with different policy evidence or payload is rejected.
- Approval policy is revalidated immediately before execution. Proposals
  expire, uncertain failures are not silently retried, and sensitive or
  external effects require fresh approval.
- Goal-to-quest execution now uses a cryptographic payload fingerprint,
  deterministic quest ID, serialized writes, durable crash recovery, and
  cross-restart duplicate prevention.
- Bounded approval and execution ledgers store status, IDs, timestamps,
  approval state, and payload fingerprints only. Raw goals, recommendation
  copy, journals, and mood notes are excluded.

## Privacy and security

- Raw journal, therapy, dream, and memory text are excluded from the Signal
  Graph. Sensitive signals are opt-in; their evidence references are omitted
  from persisted receipts while that opt-in is off.
- Every model-requested mood-history read, mood check-in write, room change,
  and tone change pauses for an explicit user confirmation. Mood-history
  sharing contains dates and numeric scores only; saved mood notes are never
  returned through the cloud tool loop.
- Ephemeral chat logging records character counts rather than raw response
  content.
- Memory encryption keys are created in OS secure storage only after the write
  is verified. Migration keeps the legacy key authoritative until its secure
  copy is verified and committed, and fails closed rather than replacing a
  missing expected key.
- Provider credentials use verified secure storage and a durable migration
  tombstone, preventing a cleared key from being resurrected from an older
  build-time value.
- Full local-data removal is a coordinated, fail-closed wipe boundary. It
  latches Safe Mode, cancels active generation, stops or drains producers and
  queued writers, clears in-memory caches, removes credentials and encryption
  keys, clears preferences, and deletes exact app-owned data and temporary
  artifacts.
- The wipe attempts every known deletion and reports all failed categories.
  Regenerable writers resume only after every step succeeds; an incomplete
  wipe remains suspended and requires attention. Safe Mode and native/provider
  credential access remain restart-latched.

## Reliability and platform safety

- Startup now renders a dependency-free first frame before any optional
  MethodChannel or plugin handshake. Missing or stale Windows runner channels
  degrade companion-window support instead of closing the primary app.
- Audio, TTS, and Rust Swarm loading are deferred until actually needed and
  permitted. Optional native binaries are no longer on the default cold-start
  path.
- One structured error pipeline owns Flutter framework, platform dispatcher,
  root-zone, and root-isolate failures on every target. Windows additionally
  records privacy-safe runner and native-crash breadcrumbs before Dart starts.
- Early-bootstrap, structured application, and Windows-native logs are bounded,
  rotated, redacted, visible in Diagnostics, exportable for support, and
  included in the coordinated local-data wipe.
- Both supported Windows rebuild paths preserve the authored runner and run an
  app-owned first-frame smoke mode against the exact packaged executable.
- Safe Mode now blocks cloud AI, native Swarm review, ambient capture, wake
  word listening, TTS playback, notification delivery, proactive cards, and
  optional startup hooks at both coordinator and service boundaries.
- Clearing Safe Mode prepares a clean next launch but intentionally keeps the
  current process latched; Diagnostics shows that a restart is required.
- Startup fails closed into Safe Mode if the Safe Boot marker cannot be read
  or updated.
- Window-manager startup is limited to supported desktop targets: the mascot
  role remains Windows-only, macOS primary-window setup is best-effort, and
  mobile/web avoid the desktop plugin path.
- The native Rust Swarm is explicitly Windows-only, with a safe web fallback,
  and macOS includes the secure-storage keychain access group.
- Removed an infinite After Storm ↔ Weekly Snapshot bridge recursion path.

## Release validation status

- Added focused tests for intelligence scoring and fusion, consent and action
  lifecycle, durable Action Loom behavior, preferences and guardrails,
  complete data wipe, provider-credential tombstoning, startup platform
  policy, bootstrap error handling, structured-log privacy, and the After
  Storm bridge.
- GitHub Actions derives Windows and Android recovery artifact versions from
  `pubspec.yaml`; verification artifacts include analyzer/test logs, the exact
  formatting patch, and the generated `pubspec.lock` when available.
- Flutter, Dart, Rust, and Windows PowerShell are not installed in this
  packaging environment. No runtime test or release-build success is claimed
  here. Run the repository workflow and `BUILD_ALL_NEURA_UPGRADES.bat` on a
  configured build host before release.
