# Emotion-Driven Posture + Lighting Patch

## What you get
- Neura breathing micro-motion (subtle, non-uncanny)
- Neura emissive/glow driven by mood + energy
- World lighting (ambient + key light intensity) driven by mood + energy
- Optional Animator posture float (0..1)

## Unity setup
1) Add `LightingMoodController` to a World root object.
   - Assign a Key Light (or it auto-finds one).
2) Add `NeuraBreathingController` to Neura (or a chest/upper-spine child).
   - Assign `breathingTransform` to the chest bone for best effect.
3) Add `NeuraGlowController` to Neura root.
   - It auto-finds renderers.
4) Add `EmotionDriver` to Neura root.
   - Assign breathing/glow/worldLighting/animator if auto-wiring misses.

## Bridge integration
Your BridgeRouter already parses `mood` and `energy` via `SET_STATE`.
After parsing, call:
`emotionDriver.SetState(mood, energy);`

(If you don't have a reference yet, add a serialized field for EmotionDriver on the router.)
