// lib/avatar/avatar_controller_viseme_ext.dart
//
// Extension methods to drive optional mouth/viseme inputs.
// Your base AvatarController stays unchanged; this adds capabilities safely.

import 'avatar_controller.dart';
import 'avatar_rive_inputs.dart';

extension AvatarControllerVisemeExt on AvatarController {
  /// Drive a numeric input like `mouthOpen` if it exists (0..1).
  void setMouthOpen(double open) {
    final value = open.clamp(0.0, 1.0);
    setNumberInput(AvatarRiveInputs.mouthOpen, value);
  }

  /// Drive a numeric input like `viseme` if it exists.
  /// Map enum index (0..N) on the asset side.
  void setVisemeIndex(int index) {
    setNumberInput(AvatarRiveInputs.viseme, index.toDouble());
  }
}
