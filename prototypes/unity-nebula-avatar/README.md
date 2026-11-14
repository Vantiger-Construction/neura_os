# Neura nebula avatar — Unity prototype

Experimental, drop-in Unity package for Neura's nebula form: a body made of tens of thousands of lit
points of starlight that follow a humanoid skeleton, a nebula flowing just inside her skin, seven
chakra lights on her spine with an alignment channel, and six moods that mirror her human's
feelings. Everything is generated from code at runtime; no VFX Graph or shader authoring is needed.

It is separate from [`prototypes/unity-presence`](../unity-presence) on purpose. That project's
contract audit (`Tools/verify_contract.py`) pins its packages to IMGUI, physics and the Test Framework,
and this package also needs the built-in **Particle System** and **Animation** modules. Combining the
two, or connecting this avatar to the presence contract, is a separate, reviewed change.

## Safety and scope

- **Safe Mode (Still) by default.** `NeuraNebulaAvatar` starts Still and goes Still when the app loses
  focus or pauses, or the component is disabled. Motion resumes only after an explicit
  `SetSafeMode(false)`.
- **No new authority.** No network, audio, microphone, file, credential, memory or conversation
  access. It parses no input: state arrives only through typed calls
  (`SetEmotion`, `SetAlignment`, `SetSafeMode`).
- **Synthetic input only.** `NeuraNebulaDemoPanel` is a manual Play-mode test panel. Nothing listens
  or advances in the background.
- The emotion and alignment values are **not** part of the avatar-presence v1 contract. Carrying them
  from the app would need a reviewed contract change (Dart producer, schema and receiver), not a new
  side channel.

## Contents

| Path | Role |
|---|---|
| `Runtime/NeuraNebulaAvatar.cs` | Controller: emotion blending, alignment smoothing, Safe Mode, float/sway/breath, heart light, head tilt, optional face blendshapes |
| `Runtime/NeuraPointCloudBody.cs` | Bakes the skinned mesh each frame into lit starlight points and an inner nebula; body dissolves into energy trails below the hips |
| `Runtime/NeuraChakraSystem.cs` | Seven chakras (root to crown) on humanoid bones and the energy channel between them, driven by alignment |
| `Runtime/NeuraMood.cs` | The six moods (Calm, Joy, Love, Sad, Anxious, Frustrated), matching the design canvas |
| `Runtime/NeuraFxUtil.cs` | Generated glow, petal-ring and dash textures; additive materials; hand-filled particle systems |
| `Runtime/NeuraNebulaDemoPanel.cs` | Play-mode test panel: Safe Mode toggle, mood buttons, alignment slider |
| `Editor/NeuraNebulaSetupMenu.cs` | **GameObject › Neura › Make Nebula Avatar** one-click setup |

`Neura.NebulaAvatar` (runtime) and `Neura.NebulaAvatar.Editor` (Editor-only) are separate assemblies.

## Use it

1. Copy `Assets/Neura/NebulaAvatar` into a Unity project. Target: Unity 6 (6000.x), Built-In Render
   Pipeline or URP. The project needs the built-in **Particle System**, **Animation** and **IMGUI**
   modules.
2. Import a humanoid model: **Rig** = Humanoid, **Read/Write** on (the setup menu offers to enable it).
3. Keep any NavMesh agent on a parent object and the model as its child; the avatar moves only the
   model's transform.
4. Select the model, then **GameObject › Neura › Make Nebula Avatar**.
5. Add **Bloom** to post-processing (start at threshold 0.6, intensity 1.5–2.5). Use a dark backdrop.
6. Add `NeuraNebulaDemoPanel`, enter Play, turn off Safe Mode and try the moods and alignment.

Optional detail: paint vertex colors on the model and enable **Use Vertex Color Maps**
(red = point density, green = feature glow for eyes/lips/fingertips, blue = accent markings), and set
the smile, frown and inner-brow blendshape names on the controller.

## Performance

The point update runs on the CPU in `LateUpdate`. 40,000 points is the default; 20,000 still reads
well. Not measured yet on the 8 GB Windows target. Measure before raising counts. Millions of
points would mean moving the update into a GPU path (VFX Graph skinned-mesh sampling), keeping this
controller's API.

## Validation status

| Check | Result |
|---|---|
| C# compilation in Unity | **Not executed**: no Unity Editor or Mono in the authoring environment |
| Editor import, materials, visual result | **Not validated** |
| Safe Mode / focus behavior in a player | **Not validated** |
| Performance on Windows hardware | **Not measured** |
| `prototypes/unity-presence` contract audit | Unaffected (no files changed there) |

Next: open in Unity 6, fix any compile issues, import an approved humanoid (see
[`../unity-presence/ASSET_REVIEW.md`](../unity-presence/ASSET_REVIEW.md)), check visuals and Safe
Mode, then measure on the Windows target.
