# Neura standalone avatar-presence prototype

Experimental Unity project, separate from the Flutter application, native
launchers, installers and release workflows. It consumes the existing
[`NeuraAvatarRuntimeSnapshot.toJson()`](../../lib/avatar/neura_avatar_runtime_bridge.dart)
v1 presentation shape through **manual synthetic input only**. It has no live
transport and is not enabled in Neura. Physical-device acceptance of the
existing app remains the release priority.

## What is implemented

- A primitive companion stands on a defined, 3 m diameter stage. A separate
  standing anchor stays fixed while the visual mount breathes and turns.
- Six existing room IDs change the stage accent; stance changes the base
  orientation. Still/Subtle/Expressive and Compact/Standard/Large control
  bounded visual transforms. The selected phase is displayed as synthetic
  status; `speaking` and `listening` never activate audio.
- The left panel applies room/motion/scale/phase selections or a manually
  entered v1 JSON snapshot. Nothing advances or receives inputs in the background.
- Unknown versions, fields, duplicate fields, missing fields, invalid types,
  unknown enum values and oversized input are rejected. Errors expose a fixed
  category, never the supplied JSON.
- Either `safe_mode: true` or `phase: "safeMode"` forces **Safe Mode + Still**,
  even if a structurally valid input requests expressive motion. Malformed
  input clears the previous animated state to a safe default.
- Boot, focus changes, pause, disable and reset return to safe Still. The
  local Safe Mode override wins over all incoming synthetic states. Returning
  to the foreground or releasing the override requires a fresh valid input.
- The prototype code has no microphone, audio playback, network, user-file,
  credential, conversation, journal, private-memory or action-service access.
  Its runtime assembly depends only on the pure contract core and Unity.

## Open the project

1. Add **this directory**, `prototypes/unity-presence`, as an existing project
   in Unity Hub. The source target is **6000.6.6f1**, using the Built-In Render
   Pipeline. This is an isolated project, not an upgrade of the Flutter app.
2. Let Unity generate its normal editor settings and resolve the manifest.
   The Test Framework is pinned to `1.6.0`; the only other declared packages
   are built-in IMGUI and physics (used to construct primitives, whose
   colliders are immediately disabled and removed). Initial editor/package
   setup may require Unity's registry; the prototype itself has no runtime
   network client. Editor import/package compatibility has not been executed.
3. Open `Assets/Presence/Scenes/PresenceStage.unity`, enter Play mode and
   enlarge the Game view if needed. It starts in safe Still. Press **Apply
   synthetic selection** to begin a synthetic presentation.
4. Try all rooms, scales and motion settings. Toggle the local Safe Mode
   override during expressive motion. Apply an unsupported `v`, then test
   losing focus, pausing and returning. Motion should resume only after a
   fresh explicit input.

The scene contains one harness. Its runtime creates only its own stage,
placeholder geometry and camera; it does not generate or overwrite saved
avatar prefabs. No Animator, AudioSource or AudioListener is created.

## Contract profile

[`Contract/avatar-presence-v1.schema.json`](Contract/avatar-presence-v1.schema.json)
records the seven typed fields and current enum domains. The receiver accepts
one flat JSON object, at most **512 characters**, in any field order with JSON
whitespace. Strings must be unescaped ASCII enum tokens, matching the current
Dart producer's `jsonEncode(snapshot.toJson())` output. Escaped equivalents,
additional properties and future/custom room IDs are intentionally rejected;
this is a narrow presentation receiver, not a general JSON deserializer.

```json
{"v":1,"room_id":"reflection_bay","phase":"thinking","stance":"reflective","motion":"subtle","scale":"standard","safe_mode":false}
```

[`Contract/synthetic-v1-states.json`](Contract/synthetic-v1-states.json) contains
six synthetic examples, one per existing room. No app content is captured.
The schema describes incoming values; the C# receiver additionally normalizes
either Safe Mode signal. This adds no authority to execute anything.

## Validation evidence — 2026-10-17

Base source inspected: `a4e8c5e793d4aa3764c66a47819c395b555c786b`.

| Check | Evidence | Result |
| --- | --- | --- |
| Actual C# core compilation and execution | Mono C# 6.8.0.105, warnings treated as errors; the same scenario source is used by Unity EditMode tests | **22 scenarios passed**, including 270 room/phase/motion/scale combinations, rejection cases, both Safe Mode signals, override/release/reset and bounded poses |
| Current Dart/receiver compatibility | `python3 prototypes/unity-presence/Tools/verify_contract.py`, Python 3.12.14 | **6 checks passed**: v1 keys/version, enum domains, room/profile mappings, synthetic fixtures, scene GUID references and source capability/dependency audit |
| Unity scene/controller/shader | Source and metadata inspected; 23 EditMode cases and 6 PlayMode tests provided | **Not executed in Unity**; Unity Editor unavailable in this environment |
| Editor import, package resolution, shader compilation and visible stage | Requires the target Unity Editor | **Not validated** |
| Native focus/background events, Windows player and Android device | Requires Editor/player builds and physical devices | **Not validated** |
| Rigged avatar import, humanoid map, materials, animation and standing fit | Existing asset was hash/structure checked; see [asset review](ASSET_REVIEW.md) | **Candidate only**; not imported or approved for this prototype |

The Python checks inspect source declarations, not executed Flutter
serialization. The C# console run validates the actual parser/session/pose
implementation; it does not simulate Unity, compile the Unity controller,
render the shader or establish physical-device behavior. No Unity screenshot,
performance measurement or finished-avatar claim is made.

### Repeat the core checks

From the repository root, with Mono `mcs` and `mono` installed:

```bash
bash prototypes/unity-presence/Tools/run_core_tests.sh
python3 prototypes/unity-presence/Tools/verify_contract.py
git diff --check
```

The shell runner uses a temporary output directory and removes it on exit.
`MCS_BIN` and `MONO_BIN` may point to local compiler/runtime wrappers.

### Execute Unity tests next

In the Editor, open **Window → General → Test Runner** and run both EditMode
and PlayMode suites. Record the exact Editor version, resolved package lock,
test XML and logs. The PlayMode tests synthesize focus/pause messages; actual
native focus/background behavior still needs manual player/device checks.

For Windows batch execution from the repository root:

```powershell
$prototype = (Resolve-Path .\prototypes\unity-presence).Path
$results = Join-Path $prototype 'TestResults'
New-Item -ItemType Directory -Force $results | Out-Null
$editor = 'C:\Program Files\Unity\Hub\Editor\6000.6.6f1\Editor\Unity.exe'
& $editor -batchmode -nographics -projectPath $prototype -runTests `
  -testPlatform EditMode -testResults "$results\editmode.xml" -logFile "$results\editmode.log"
& $editor -batchmode -nographics -projectPath $prototype -runTests `
  -testPlatform PlayMode -testResults "$results\playmode.xml" -logFile "$results\playmode.log"
```

Inspect results and failures; these commands have not been run here. A
graphical Editor session remains necessary for visual/shader acceptance.

## Approved assets and integration remain separate

[`ASSET_REVIEW.md`](ASSET_REVIEW.md) identifies the existing offline GLB and
historical scripts. Reuse that source and its offline import checklist after
asset approval and importer validation. The named **Visual mount** is the
replacement seam for passive, locally imported mesh geometry. Keep it
feet-aligned and within the stage at all scales. The prototype owns its
transforms; third-party scripts, Animator/root motion, lip-sync and autonomous
behaviors are outside this seam and need separate review and safety tests.

No legacy command server, audio subsystem, avatar model download, Unity player
launcher or Flutter subscription has been added. A future live bridge needs
its own lifecycle, session authorization and freshness design; do not turn
`ApplySyntheticSnapshot` into a listener as part of release packaging.

Remaining acceptance: approve the avatar/rights and pinned local importer,
import and save a verified prefab, run Editor tests and visual QA, validate
Windows and relevant Android hardware, then review any proposed app
integration. The existing Notion task remains **Needs verification**. No
automatic merge, deployment or production enablement is authorized here.

Editor reference: [Unity release archive](https://unity.com/releases/editor/archive).
Test setup follows [Unity test assembly guidance](https://docs.unity.com/en-us/engine/6000.0/manual/packages-list/cus-pkg-development/cus-tests)
and the [Test Framework 1.6 documentation](https://docs.unity3d.com/Packages/com.unity.test-framework@1.6/manual/index.html).
