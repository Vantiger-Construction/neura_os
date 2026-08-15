# Neura consolidated upgrades

This source tree combines the upgrades available in the August 2026 recovery
workspace without discarding the app's existing modules.

## Integrated

- Existing Flutter Neura OS with wellness, clinical-support, legacy, memory,
  voice, avatar, money, goals, notifications, and swarm modules preserved.
- Secure OS-backed Anthropic credential storage and in-app provider settings.
- One-time migration away from build-time provider secrets.
- Neura Link v1 typed WebSocket protocol.
- Live `speak_delta` assembly, terminal `speak`, and barge-in interruption.
- Tone events, dispatch-intent hook, connection state, diagnostics remedies.
- Optional sidecar lifecycle manager with bounded restart/crash-loop guard.
- Rust `neura_api` local-brain executable on `127.0.0.1:8787`.
- Windows one-command local-brain build/run script.
- Dart protocol and credential validation tests plus Rust envelope test.
- Append-only Timeline Vault with tail index and export.
- Crash-loop-aware Safe Boot and live Module Health Monitor.
- Diagnostics recovery controls and reliability tests.

## Run locally

1. Run `RUN_NEURA_LOCAL_BRAIN.bat` and leave its window open.
2. Run Neura using the existing `RUN_NEURA_LOCAL.bat`.
3. Open Settings > Local Brain Console.
4. Refresh Diagnostics, then send text to verify streaming and interruption.

The local-brain executable intentionally uses a safe echo adapter for protocol
verification. Neura's established primary chat continues to use the secure
provider credential and retains its guardrails, room tools, memory policy,
retry behavior, and local fallback.

## Release safety

- Do not build with `--dart-define=ANTHROPIC_API_KEY=...` after migration.
- Revoke any key previously distributed inside a ZIP or executable.
- A compiled Windows or Android release must pass Flutter analysis/tests and
  Rust tests on a machine with those toolchains installed.
