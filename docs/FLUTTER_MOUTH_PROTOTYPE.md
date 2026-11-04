# Visible local-speech prototype

This opt-in Flutter renderer draws an independently moving mouth using the
existing Windows SAPI visemes from PR #158. It adds no package, native plugin,
asset download, model, cloud request or microphone activation. It is a synthetic
portrait for validating visible articulation, not Neura's final character rig.
The default character, speech preferences and disabled startup greeting retain
their existing behavior. This work must receive independent review before merge.

## Try it on Windows

1. Build this feature together with the pinned conversation/motion sources below,
   or use a reviewed build containing all four features. Record the commit/tree,
   build identity, Windows version, installed SAPI voice and audio output device.
2. Open **Settings → Select Avatar → Neura speech prototype**. This opens a
   dedicated preview with synthetic artwork; opening it starts no speech or
   microphone. The selected main avatar and floating mascot retain their art.
3. Press **Play local sample** to hear a fixed local sample through the existing
   speech service. Production playback is disabled outside Windows. The portrait
   renders at 240 logical pixels. The mouth
   remains closed until the first SAPI phoneme event; it does not estimate Windows
   lip movement from the reply text or from the native start acknowledgement.
4. Listen to a local sample such as “Mama, Papa, baby. We owe you a blue balloon.”
   Verify visible closure around p/b/m, broad vowels, rounded w/oo/o and closed lips
   during pauses. Try at least two installed voices and normal/slow speech rates.
5. Interrupt with **Speak again** and with **Stop**; Back also stops the preview. Repeat with Safe Mode, app
   minimize/background, restore, route coverage and avatar selection changes.
   There must be no stuck open mouth, stale restart or automatic speech recovery.
   Returning from a suspended renderer requires a fresh speech onset. Opening
   the prototype during an utterance leaves it resting until a new sample.
6. Record latency observations with audible speech and the actual rendered
   character. Check CPU/memory and responsiveness alongside the existing local
   model on the user's laptop with 8 GB RAM or less. Synthetic tests and CI builds
   do not establish this resource or physical lip-sync acceptance.

Do not mark physical acceptance complete without testing audible speech and the
rendered avatar on the user's Windows PC. Existing SAPI polling is approximately
40 ms; it delivers the latest audio-clock shape, so short phonemes may be missed.
This prototype does not change the native event protocol or promise exact
phoneme/audio alignment. See `AVATAR_CONVERSATION_VALIDATION.md` for the broader
conversation and device acceptance checklist when integrating PR #157.

## Rendering and asset contract

`NeuraMouthPose.fromInputs(viseme, mouthOpen)` consumes the canonical controller
numbers. Non-finite, fractional or unknown shape IDs rest safely; openness is
bounded to 0–1. `rest` and `MBP` always close, even if another producer supplies
positive openness. The painter distinguishes broad/rounded shapes, upper teeth
and tongue hints. Several phonemes share a drawing, matching Neura's compact
viseme enumeration; this is not a photorealistic facial-animation system.

`NeuraMouthLayer` composes a mouth over a mouth-free child. Its `mouthBounds` is a
normalized rectangle relative to that child's entire finite canvas, including
padding. The synthetic 200×200 canvas uses `(0.37, 0.56, 0.26, 0.14)`; those numbers
are specific to the portrait. The static face and changing mouth have separate
repaint boundaries. There is no per-frame ticker, tween, timer or idle redraw in
this renderer. Pose changes repaint the small mouth region; completion closes
immediately. Accessibility reduced motion, disabled route tickers, Safe Mode,
backgrounding and `enabled: false` return to neutral. Observer/controller
listeners detach on disposal. Recovery never replays a cached open pose.

The inspected `assets/images/neura_fullbody.png` is a single painted 1100×1500
image, including its mouth and teeth. Its mouth is only about 25 source pixels
wide, becoming roughly 2–3 pixels at common in-app sizes. Overlaying a flat mouth
on it would leave the original lips visible and cannot deform cheeks or jaw.
The Rive view still passes through its fallback, because the current Windows
build lacks the required ClangCL setup. Reintroducing Rive is unnecessary for
this prototype.

To retain Neura's final appearance, provide one of these assets:

- A front-facing portrait/body layer with the existing mouth fully removed,
  transparent background, a known canvas size and padding, a documented mouth
  anchor rectangle, and sufficient display scale for a mouth at least 12–16
  logical pixels wide. For a 2D prototype, use that image as the child of
  `NeuraMouthLayer` and calibrate its normalized bounds. Use a portrait crop for
  smaller surfaces so articulation remains visible. The generic painted lips
  will still need art-direction approval to match her skin/lip style.
- For convincing deformation in the current realistic character, a compatible
  face/jaw rig or aligned transparent mouth layers covering rest, sealed MBP,
  broad vowels, rounded O/U/WQ, FV, teeth and tongue shapes, with permission to
  redistribute them. Supply shared canvas/pivot coordinates and interpolation
  rules, plus a jaw/cheek mask if deformation is needed. A 3D rig must supply the
  equivalent blendshapes and a supported renderer; the current PNG cannot serve
  as that rig.

The reusable pose/layer interface provides the 2D insertion point. No final
character asset is fabricated or downloaded. The separate Windows mascot is
explicitly outside this smallest rendering prototype: it continues to display
the original art and PR #149's body/lifecycle behavior. A later mascot lip rig
must use equivalent mouth-free art and forward bounded content-free poses over
its existing local bridge, including owner/activity invalidation. This PR does
not send reply text across that bridge.

## Automated validation

The feature branch is stacked on PR #158
`fe97cf8016fe64cdc1bcb2258e1440a65aeb6299`, keeping the review delta confined to
rendering, the opt-in preview and removal of Windows' guessed initial mouth.
The disposable integration additionally composes:

| Source | Pinned head |
| --- | --- |
| PR #157 conversation | `e42d5bdc46504971e4193641a0e2049819b78f38` |
| PR #149 motion | `3269cddde9589c6c38ce275cc9319f73e8469ff9` |
| Neura target | `640dedf6612c3cf91824bfc4152e3a4fbc3c663f` |

`test/avatar/flutter_mouth_sapi_test.dart` exercises the real Dart Windows adapter,
speech service, viseme bridge, event bus, orchestrator, controller and rendered
mouth with synthetic native-channel responses. Pixel comparisons and checked-in
goldens cover rest, open AI, rounded WQ and sealed MBP. Regressions cover terminal
events, replacement, delayed acknowledgements/polls, synchronous cancellation
before native purge, Safe Mode, background/restore, reduced motion, disabled
tickers, controller replacement, disposal and stale callbacks. These fixtures
do not synthesize audio or call a microphone, model or network service.

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub test/avatar/flutter_mouth_sapi_test.dart
flutter test --no-pub --concurrency 2 --dart-define=NEURA_VALIDATE_NATIVE_VISEMES=true
```

The immutable-action `neura-visible-mouth.yml` workflow composes the pinned
sources in disposable Linux/Windows checkouts, runs the full Flutter suite,
compiles/tests the actual Windows SAPI owner without audio and builds the release
Windows application. Source-head drift fails explicitly. It never pushes the
combination or merges the PR. Hosted Windows compilation is separate from audible
physical-device acceptance; independent approval remains a merge prerequisite.

The speech evidence manifest refreshes only the changed bridge fingerprint. Its
historical reference is not a build attestation; the existing Windows CMake
fingerprint already differs on the #158 baseline. Record the actual final Git
commit/tree and bundle hashes for a physical test rather than treating that
manifest as proof of the combined build.
