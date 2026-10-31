# Neura body motion

Neura has one continuous procedural body (`lib/avatar/motion/`). Every avatar
surface — room presence, global host, presence view, and the floating desktop
mascot — renders her full-body art through the same spring-damped engine, so
state changes, mood shifts and gestures blend instead of snapping.

## What drives her

| Source | Effect | Where |
|---|---|---|
| Presence phase (idle / listening / thinking / speaking / error) | Base posture, breath rate, aura | `NeuraCompanionPresence`, bus events |
| Visemes (`NeuraMouthOpenEvent`) | Speech-synced body lift | TTS viseme bridge |
| Her speech rhythm | Opening nod, question tilt, exclamation hop, trailing settle — synced to TTS word progress, timer fallback otherwise | `NeuraSpeechBeats` |
| Brain `set_tone` | Mood/energy posture + one flourish | `NeuraToneMotion` |
| Brain `avatar_cue` | Deliberate gesture and/or mood | `NeuraAvatarCueGate` |
| Her own idle attention | Glances, weight shifts, settling, stretches, happy hops (weighted by mood/energy) | `NeuraMotionEngine` |
| Room stance | Lean bias per room (matches Unity `PresentationPose`) | `NeuraAvatarRuntimeBridge` |

## Brain protocol (for `neura-api`)

Both are ordinary v1 envelopes on the existing link. Neither changes any
existing kind.

```json
{"v":1,"kind":"set_tone","id":"t1","data":{"tone":"warm"}}
```
Tones: `calm`, `warm`, `focused`, `hopeful`, `alert`, `neutral`.

```json
{"v":1,"kind":"avatar_cue","id":"c1","data":{"gesture":"nod","intensity":0.6,"mood":0.4,"energy":0.7}}
```
- `gesture` (optional): `nod`, `double_nod`, `tilt_left`, `tilt_right`,
  `bounce`, `lean_in`, `lean_back`, `shake`, `wave`, `settle`, `celebrate`,
  `shrug`.
- `intensity` 0..1, `mood` −1..1, `energy` 0..1 — all optional, clamped.
- Any other key, unknown gesture, wrong type or non-finite number is dropped.
- Rate limit: ≥350 ms apart, ≤6 per 5 s. Extra cues are ignored, not queued.

Suggested brain-side approach: have the model end its turn with a structured
field (or a tool call scoped to the current `RoomProfile`) choosing one tone
and at most one gesture, validate in Rust against the same allow-list, and emit
`set_tone` before the first `speak_delta` and `avatar_cue` alongside it. The
Flutter side never parses reply text as commands.

## Safety

- Safe Mode → body freezes to exact neutral; all cues and idle behaviour stop.
- "Still" preference and OS reduced-motion → no motion, no gestures.
- Cues are presentation-only: no text, no content, no authority.
- The Unity `AvatarSnapshot` v1 contract is unchanged.

## Lifecycle and regression validation

`NeuraAnimatedBody` observes the application lifecycle, including its initial
state. In-app bodies stop sampling and reset to neutral outside `resumed`, when
their effective `TickerMode` is disabled, under OS reduced motion, or when
`animate` is false. Resuming or uncovering a route restores eligible motion.
Replacing a custom sampler updates the runtime subscription; disposal removes
the lifecycle observer, listener and ticker.

The shared runtime also suspends for background, Safe Mode, restart-required
recovery and Still. Backgrounding clears activity and mouth state. Stop disposes
subscriptions and cancels the error timer. Speech completion, cancellation,
failure and explicit Stop cancel fallback beats and discard queued body motion.

The Windows mascot owns a separate engine and uses `respectAppLifecycle: false`:
an inactive, non-focused mascot window must not independently veto an authorized
main-window signal. It starts frozen and requires a versioned `body` message with
`active: true`, `safe: false` and an explicit supported motion level. The main
bridge sends inactive/safe state on background, recovery and shutdown. Its body,
entrance and pulse tickers still honor Safe Mode, Still and OS reduced motion.

The focused corrections originate in PR #150 at
`c63d2bd9f50b11348ab0f5e532f2e4ccb5893b5e`. No unrelated memory, reference or task
transfer changes are included in this port to PR #149.

Regression coverage includes all non-resumed lifecycle states, mounting while
inactive, foreground recovery, neutral transforms, effective ticker masking,
an actual Navigator covering route and pop, room transitions, sampler changes,
disposal, Safe Mode/recovery/Still, and terminal speech paths. Mascot tests use
synthetic window messages and mocked platform methods, without native windows
or audio. `.github/workflows/neura-avatar-motion.yml` runs scoped analysis,
formatting and these regressions on Ubuntu and Windows with Flutter 3.47.5.

Local port validation on October 30, 2026: all 924 Flutter tests passed, including
the 83 focused motion/room/speech tests. Those 83 also passed against #150's
integrated source; normalized Dart ASTs match for all seven ported production
files. Three original #150 regressions fail against unmodified #149, confirming
the background and Still defects in controlled tests. Scoped analysis of all
11 changed Dart files and canonical formatting passed. Ten security-helper tests
passed; the checksum-pinned OSV scan reported zero advisory matches across the
unchanged Dart/Rust/npm locks (227/213/1 packages). Hosted current-head CI and
independent review remain separate merge gates.

Automated test and build results do not establish physical-device acceptance.
Actual Windows mascot focus/minimize/restore, native speech synchronization and
Android background/foreground/room animation behavior remain unverified. Those
checks must use identified builds on real devices; startup speech stays disabled
pending the separate Windows speech acceptance process.

## Swapping in real animation later

If a Rive or Lottie asset is added to `assets/rive/` or `assets/animations/`,
`AvatarView` renders it and the procedural body still layers on top
(`animateBody: false` turns that off per surface).
