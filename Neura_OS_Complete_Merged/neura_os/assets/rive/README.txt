Neura Rive Rig Drop Zone
=======================

Put your compiled Rive file here:
  assets/rive/Neura.riv

Recommended Rive setup
----------------------
State Machine name:
  NeuraBrain

Inputs expected by the Flutter driver (lib/neura_shell/widgets/neura_rive_resident.dart):
  - isWalking (bool)
  - talkLevel (number)
  - rest (number)
  - aa   (number)
  - ee   (number)
  - oo   (number)
  - ff   (number)
  - mm   (number)

Notes
-----
- If Neura.riv is missing, the app falls back to assets/images/neura_fullbody.png
  so builds never break.
- If your state machine / input names differ, edit the mapper in:
    lib/neura_shell/widgets/neura_rive_resident.dart
