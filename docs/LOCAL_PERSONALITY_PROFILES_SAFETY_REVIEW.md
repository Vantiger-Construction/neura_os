# Local profile return: security review and preservation safeguards

Review date: November 6, 2026 (America/Chicago).
Inspected default branch: `a74330c25e79a07bf3d70724cc50f09c473aa1c2`.
Original implementation: [PR #186](https://github.com/Vantiger-Construction/neura_os/pull/186),
merged as `7810959c50acef23383be40aa95188284b5d3859`.

## Decision

A safe return for existing installations cannot be established by the current
profile selector, markers or shared installation key. This correction holds
new activation and improves preservation guidance. Existing profiles remain
usable. It neither unlocks retained data nor claims to recover an installation
that is already in profile mode. Independent review is required before lifting
the setup hold or introducing a return path.

The original ten profile regressions passed on the inspected base. A new
synthetic preservation regression then reproduced successful activation on an
installation containing encrypted memory and a journal fixture, confirming the
missing setup safeguard before this change.

## Inspected boundaries

All paths below refer to the inspected commit unless describing this correction.

| Component | Finding and consequence |
| --- | --- |
| `lib/profiles/local_profile_service.dart` | `enabled` is true for a live latch or the presence of either `neura.local_profiles.enabled.v1` or `neura.local_profiles.encrypted.v1`, even a false sentinel. The old first durable write was empty ciphertext, followed by the sentinel. Missing/corrupt ciphertext fails closed. Removing the final profile writes an encrypted empty registry and preserves the gate. Neither marker identifies an owner. |
| `lib/profiles/local_profile_gate.dart`, `lib/src/app.dart` | The installation Navigator and private routes are removed from the mounted tree. Clearing the gate would remount routes containing installation data without an owner-specific authorization check. |
| `lib/startup/neura_startup_coordinator.dart` | Profile boot takes a restricted path before private controllers, cloud sign-in, notifications or saved startup voice are initialized. Flipping a UI toggle cannot safely reconstruct the ordinary startup path. |
| `lib/core/memory/memory_crypto.dart` | The registry and existing encrypted records share `MemoryCrypto`'s AES-GCM key from the OS credential store (`neura.memoryGraph.seed.v2`). The secure marker and legacy migration protect key continuity, not separate people using the same OS login. Replacing/deleting the key would strand existing ciphertext. |
| `lib/widgets/auth_guard.dart`, `lib/services/app_lock_prefs.dart` | Device authentication is optional and has an in-app disable path after failure. It authenticates the OS user, not the original owner among people sharing that login. It cannot establish a new trustworthy return boundary. |
| `lib/encrypted_memory/companion_memory_service.dart` | Profile mode rejects prior grants and new uses, including delayed local-owner loads. Local scope IDs are authorization metadata; they do not authenticate a person or prove historical ownership. |
| `lib/profiles/local_profile_runtime.dart` | Switching revokes generation/memory authority, locks the vault, stops producers and drains native session ownership before selection. The secondary mascot engine remains suspended. Background, Safe Mode, recovery and restart revoke selection. A future return must meet these same boundaries. |
| `lib/src/core/data_wipe_service.dart` | Full wipe latches Safe Mode, revokes/drains writers, verifies preference and device-key deletion and reports unconfirmed deletion. Existing profile handles cannot resume. This is destructive deletion, not a way to preserve and restore installation data. |

## Why a reversible toggle is insufficient

Someone sharing the OS application can select, edit or remove any profile. That
person can also read either mode marker through the same application storage
authority. No existing enrollment distinguishes that person from the original
installation-data owner. A new PIN chosen after activation, selecting the oldest
profile, removing every profile, clicking a confirmation, authenticating the
shared OS login, or signing in to an unrelated cloud account cannot prove that
historical ownership. Neither an empty selector nor missing data is evidence
that installation routes are safe to expose.

Blocking only when known journal/memory keys exist would also be insufficient:
private installation data spans preferences, files, vaults and credentials.
An incomplete inventory or failed read cannot establish that an installation
contains nothing valuable. This patch therefore refuses all new activation,
including apparently empty installations. No data scan, migration, key rotation,
plaintext export, model request or destructive reset is performed by that refusal.

## Focused changes

- Replace the activation dialog with a setup-hold explanation while keeping
  ordinary persona editing available. Retain a service-level refusal so a stale
  caller cannot bypass the UI. Refusal leaves ordinary and existing profile
  session ownership intact and performs no storage or cryptographic operations.
- Preserve both markers, registry format, key ownership, restricted startup and
  private-route exclusion for existing installations. Existing profiles still
  create, select, edit, switch and remove using their verified encrypted store.
- Explain retained-data and restart/final-removal limits on the selector.
  Place permanent deletion in a collapsed Data deletion section and keep its
  explicit confirmation. A changed session epoch invalidates an open deletion
  confirmation. No deletion operation implements a return.
- Document the remaining requirements and use synthetic pre-existing registries
  to exercise compatibility without a production activation override.

## Requirements before reversible switching

1. **Owner enrollment and recovery:** establish a verified owner authority
   before sharing or migrating an ordinary installation. Define a trustworthy
   recovery route for already-enabled installations; new credentials alone
   cannot retrospectively establish ownership. Authentication failure must keep
   records encrypted and access closed without deleting them.
2. **Protected storage ownership:** bind the installation key and every private
   store to that authority. Review independent key wrapping, per-owner storage
   and credential access together; a display name and the current shared key
   cannot supply those boundaries. Keep old ciphertext/key material intact until
   a recoverable migration and its readback are confirmed.
3. **Durable transitions:** use an authenticated, crash-recoverable transition
   record with ordered commits, readback and rollback/recovery semantics. Test
   power loss, stale preference caches, rejected/misreported writes, missing
   credentials and partial migration at every commit point. A missing marker
   must never default to private installation access.
4. **Lifecycle and capabilities:** revoke epochs, chat/context caches, editors,
   private routes, exact-request cloud approvals and scoped memory grants;
   cancel/drain all generation, capture, speech, notifications and secondary
   engines before mounting the next owner. Restart from an unselected/locked
   state. Reacquire owner permissions explicitly; voice/microphone opt-in and
   cloud approval cannot carry across the boundary. Safe Mode stays microphone-off.
5. **Sharing and deletion:** continue explicit, scoped sharing. Keep full wipe
   separate from return, with writer drain, verified deletion and terminal old
   handles. No automatic profile memory import, cloud fallback, model download
   or routing change may accompany switching.
6. **Independent validation:** exercise unauthorized return attempts, session
   races, failed native stops, background/resume, restart, Safe Mode and wipe
   concurrently with synthetic encrypted journals/vaults/notes. Prove both
   unauthorized denial and authorized non-destructive recovery, then test actual
   Windows/Android key stores and lifecycle behavior before claiming acceptance.

## Validation and limits

The accompanying profile tests cover existing selection/switch/restart, failed
and misreported saves, unconfirmed shutdown, stale editors/output/approvals,
Safe Mode/recovery, corrupt/missing registries and admitted writers racing wipe.
New tests cover setup refusal without changing ciphertext, keys or current
permissions, unavailable preference operations, ordinary persona editing,
existing active sessions, last-profile removal/restart, partial markers and
cancelled/stale deletion confirmation. The existing mocked central-wipe test
continues to validate deletion independently; it does not demonstrate return.

All fixtures use disposable synthetic storage and mocked external capabilities.
No valuable data is erased for this investigation. No physical Windows laptop
or Samsung SM-S366V, actual OS authentication/key migration, microphone shutdown
or deployment is claimed. No native code, dependencies, lockfiles, model limits,
release artifacts or stored-data formats change in this correction.

Exact final validation results and the proposed source tree are recorded in the
review pull request. This document describes the security decision, not a
completed recovery implementation.
