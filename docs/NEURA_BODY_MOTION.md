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

## Swapping in real animation later

If a Rive or Lottie asset is added to `assets/rive/` or `assets/animations/`,
`AvatarView` renders it and the procedural body still layers on top
(`animateBody: false` turns that off per surface).
