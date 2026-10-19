# Existing avatar material — inspected 2026-10-17

This review precedes creation of the isolated prototype. Archive labels are
not evidence of production readiness or current asset approval. Existing
material was inspected without overlaying it onto the current application.

## Offline avatar source

`Neura_Production_Avatar_Offline_v1.zip`:

- Archive SHA-256:
  `f836e1bc6da01993727a7940c67f400c2eab97056ba1713ae0d14afe4d467f99`.
- `Assets/Neura/Avatars/Production/Neura_Production_Avatar.glb`:
  **22,363,820 bytes**, SHA-256
  `82f5dc3e839d34b00da9dce774f470d1cff10cce09dd6975445237ed99629b0e`.
  Recalculation matches the existing `Docs/AVATAR_ASSET_MANIFEST.json`.
- Direct GLB header/JSON inspection: glTF Binary v2, declared/actual byte
  length match, 1 mesh, 1 skin, 1 animation, 26 nodes and embedded buffer data.
  No external image/buffer URI was found. Material extensions include
  `KHR_materials_specular` and `KHR_materials_ior`.
- The existing archive includes a standalone offline import checklist and
  asset inventory. Its preview is a reference image, not a Unity execution
  record. It does not include a finished Unity scene/prefab project.

**Reuse decision:** retain this verified source/hash and existing checklist
as the candidate asset path. Do not regenerate the model or introduce a Meshy
runtime client. Do not copy the 22 MB binary into this placeholder prototype
until the avatar is approved and a local importer has been selected and
tested. Binary structure alone does not prove visual quality, ownership or
license suitability, rig retargeting, clip usefulness, blendshapes, material
compatibility, mobile resource use or Safe Mode compliance of a future rig.

## Historical presence bundle

Two available `NeuraCompanion.zip` copies were byte-identical:

`eb7404c81887278af56ae4ab22dfe2a3b66e8feb51d283848c91ef463ae122b3`.

The archive contains 170 entries, 189,743 uncompressed bytes, including five
Unity C# files: `NeuraIpcServer`, `NeuraLipSync`, `NeuraPresence`,
`NeuraRoomManager` and `NeuraAvatarController`. No `Packages`,
`ProjectSettings`, saved scene or prefab was found in this bundle.

Direct source inspection shows an older command envelope carrying text and
audio paths, a localhost TCP server, audio loading/playback, speech/lip-flap
behavior and ambient cursor/wander behavior. It does not implement the
current seven-field v1 presentation snapshot. Importing those scripts would
add unrelated authority and infrastructure to a presentation-only exercise.

**Reuse decision:** use the historical findings as evidence; do not port its
server, audio, speech or command code. Reuse the current Dart contract rather
than creating a replacement protocol. A minimal standalone scene/harness is
necessary because this inspected bundle supplies scripts, not a verified
project. Older archives not examined during this task remain unverified.

## Current repository and remaining decisions

At `a4e8c5e793d4aa3764c66a47819c395b555c786b`, the current root app contains
the provider-neutral Dart bridge and Flutter avatar renderers, not a verified
standalone Unity project. The
[July recovery manifest](../../docs/recovery/Neura_Recovery_Manifest_2026-07-27.md)
also identifies historical Unity material as prototype evidence. The
[startup-animation documentation](../../docs/NEURA_STARTUP_ANIMATION_AND_EFFICIENCY.md)
explicitly describes image transforms, not a skeletal/speaking Unity avatar.

The new stage uses original Unity primitive geometry with its own simple
shader. It needs no downloaded character or provider account.

Before adding a real character, record approval of the exact asset and
rights, importer name/version/license, offline import results, material
support for the extensions above, rig/clip mapping, static foot bounds at all
three scales and a verified prefab path/hash. Animation/Animator control needs
a separate Safe Mode design; only passive meshes are supported by the present
visual mount. Keep the task **Needs verification** until Editor and device
acceptance is recorded; retain the physical-device release priority.
