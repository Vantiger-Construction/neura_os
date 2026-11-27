# Recovered Lounge preview

This preview reuses one historical Lounge image and six room interaction
identities in Neura's isolated Windows sample app. It lets reviewers assess
the room composition and interaction choices with fictional content and
current wellbeing screen ports.

The image is concept/backplate artwork. It does not establish a finished,
walkable 3D room, a Unity integration, or physical-laptop acceptance.

## Source and provenance

The integration starts from repository commit
`ed8fa75a4b5d22370fa9f71a793f57cd331f2c2f`.

| Item | Recorded identity |
| --- | --- |
| Source archive | `NeuraCompanion_FullApp_Working_Unity.zip` |
| Archive size | 127,972,201 bytes |
| Archive SHA-256 | `787b0754f090eeaf2a2d6882ceab27abea5a1d9d97c8f251e79b70985d9f40e6` |
| Original image path inside archive | `NeuraCompanion_FullApp_Working/LocalApp/assets/rooms/lounge.png` |
| Recovered repository image | `assets/preview/lounge/lounge.png` |
| Image size and dimensions | 237,448 bytes; 1600 × 900 pixels |
| Image SHA-256 | `1bc3c836dbcf2787ba41867566c5c255c80438b767b4741126da7c917586adf7` |
| Image transformation | None; copied byte-for-byte |

The six interaction identities come from the `Lounge` room in
`NeuraCompanion_FullApp_Working/UnityProject/Assets/Neura/FinishedRooms/Resources/Neura/FinishedRooms/neura_finished_room_profiles.json`
inside the same archive. That source JSON has SHA-256
`b198b1fcf823a5e55b4ba54308888d4ecd8a7b686297c78b4ec691b64b46f420`.

Machine-readable provenance is recorded in
[`assets/preview/lounge/provenance.json`](../assets/preview/lounge/provenance.json).
The original room descriptions, completion labels and Unity coordinates are
historical source data; they are not evidence that the described behavior has
been accepted in the current application.

## Interaction mapping

The preview preserves the source hotspot and mode identities. It supplies
new, explicitly fictional content and uses the existing demo session when
opening a wellbeing screen.

| Choice | Source hotspot | Source mode / intent | Preview behavior |
| --- | --- | --- | --- |
| Talk | `sofa_seat` | `conversation` / `conversation` | Shows sample conversation prompts. It does not start a model or microphone. |
| Brainstorm | `coffee_table` | `brainstorm` / `brainstorm` | Shows fictional idea choices. **Try a small step** opens the existing preview `WellbeingDestination.smallStep` screen. |
| Reflect | `reflection_window` | `reflection` / `deep_reflection` | Shows a sample reflection question. **Try quiet writing** opens the current `GuidedSupportScreen` quiet-writing destination through the in-memory support port. |
| Memory | `memory_cards` | `memory` / `memory_reflection` | Shows clearly labelled fictional sample reflections. It does not open saved records. |
| Office | `office_handoff` | `office` / `send_to_office` | Shows the Office handoff concept. **Try a small step** opens the current small-step screen; no Office room is opened. |
| Spa | `spa_handoff` | `spa` / `spa_reset` | Shows the quiet-pause concept. **Try guided support** opens the existing demo settle destination. |

The original profile names `Office` and `Spa` as the corresponding source
handoff targets. The mapping above describes the narrower behavior of this
preview.

Hotspot positions are newly authored normalized 2D image coordinates. They
are not a camera projection or conversion of the archive's Unity
`localPosition` values. The original Unity positions are retained only as
provenance. Image markers are shown when the scene is at least 600 logical
pixels wide and the text scale is at most 1.5. The same labelled text choices
remain available at every supported size and text scale.

## Preview boundaries

- Entry is through **Lounge preview** in the isolated `NEURA_DEMO` app.
- Content and selections belong to the in-memory synthetic preview session.
  Lounge selections reset on **Reset**, disposal/reopening and backgrounding.
- The Lounge screen is static and adds no timers. Its linked support screens
  retain their existing lifecycle and cancellation behavior.
- The integration uses current wellbeing screen ports. It does not import the
  historical JavaScript app, CompanionHost, plaintext browser storage, Unity
  player, model configuration or voice implementation.
- The preview does not open production records or enable cloud processing,
  model downloads, microphones or speech. The isolated host and its existing
  fail-closed handshake remain the entry boundary.

The image decode request is bounded to `cacheWidth: 1280` and
`cacheHeight: 720`. One 1280 × 720 RGBA buffer is 3,686,400 bytes, approximately
3.52 MiB. This is arithmetic for one buffer, not measured application RAM;
framework, GPU and other resource costs still need physical-device
measurement.

## Open the Windows preview

From the repository root on Windows, use the repository-pinned Flutter SDK
and already-restored locked dependencies:

```powershell
flutter run -d windows --debug --no-pub --dart-define=NEURA_DEMO=true
```

Confirm the sample-data banner, then select **Open lounge preview** from the
wellbeing home. Use fictional content throughout. A missing or failed isolated
host handshake must keep the preview unavailable rather than enter production
startup.

Use the six labelled choices to inspect the details and the mapped wellbeing
screens. Try the text controls at a compact window size and with increased
text scale. Check **Reset**, leaving/reopening the screen and backgrounding
the app. Flutter hot restart (`R`) resets the whole sample session.

See [Wellbeing preview and user controls](WELLBEING_PREVIEW_AND_CONTROLS.md)
for the host boundary, existing screen behavior and validation commands.

## Validation record

Local checks recorded on November 26, 2026 using Flutter 3.47.9 and Dart
3.13.7. The PR records the committed source identity and subsequent CI results.
These checks use synthetic data and do not establish physical-device acceptance.

| Check | Status |
| --- | --- |
| Asset/provenance integrity verification in the candidate | Passed: archive/image/profile hashes, source byte equality, dimensions and six mappings |
| Focused preview tests | Passed: 17 tests across the existing demo and new Lounge suites |
| Native preview host configuration checks locally | One source check passed; three configuration checks blocked by missing CMake |
| Static analysis | Passed: `dart analyze --fatal-infos`, no issues |
| Windows isolated-preview build | Pending |
| Desktop composition and image-marker selection in a Flutter widget harness | Reviewed at 1280 × 1000; native Windows visual acceptance pending |
| Native Windows keyboard and screen-reader use | Pending |
| Compact window and increased text-scale behavior | Widget tests passed, including missing artwork at 360 × 800 and 2× text; physical acceptance pending |
| Reset, disposal/reopening and background behavior | Widget tests passed; physical acceptance pending |
| Linked wellbeing screens through current in-memory ports | Widget tests passed with no secure-storage calls or production preferences opened |
| Physical Windows laptop memory and rendering measurements | Pending |

The historical package's syntax and asset checks do not establish current
Windows visual, speech, accessibility or performance acceptance. This 2D
preview does not run Unity, so it supplies no Unity import, player-build or
performance result.
