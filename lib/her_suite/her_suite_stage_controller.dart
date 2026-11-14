import 'package:flutter/foundation.dart';

import '../avatar/neura_avatar_runtime_bridge.dart';
import '../reliability/safe_boot.dart';

/// The display-only stage choices for Her Suite: lighting mood, camera
/// framing and whether Neura is resting.
///
/// Every choice goes through [NeuraAvatarRuntimeBridge.updateStage], so the
/// Flutter stage and the Unity renderer (over the presence bridge) show the
/// same thing. None of these values carry user content; they are enum names.
///
/// Safe Mode always wins: while it is on, Neura cannot rest and any rest in
/// progress ends at once.
class HerSuiteStageController extends ChangeNotifier {
  HerSuiteStageController({
    void Function(NeuraStagePresentation stage)? publish,
    ValueListenable<bool>? safeMode,
  })  : _publish = publish ?? NeuraAvatarRuntimeBridge.instance.updateStage,
        _safeMode = safeMode ?? SafeBoot.instance.safeMode {
    _safeMode.addListener(_onSafeMode);
  }

  final void Function(NeuraStagePresentation stage) _publish;
  final ValueListenable<bool> _safeMode;
  NeuraStagePresentation _stage = NeuraStagePresentation.defaults;
  bool _closed = false;

  NeuraStagePresentation get stage => _stage;
  bool get safeMode => _safeMode.value;
  bool get resting => _stage.activity == NeuraCompanionActivity.resting;

  void setLighting(NeuraStageLighting lighting) =>
      _set(_stage.copyWith(lighting: lighting));

  void setCamera(NeuraStageCamera camera) =>
      _set(_stage.copyWith(camera: camera));

  /// Returns false, and changes nothing, while Safe Mode is on.
  bool rest() {
    if (_safeMode.value) return false;
    _set(_stage.copyWith(activity: NeuraCompanionActivity.resting));
    return true;
  }

  void wake() =>
      _set(_stage.copyWith(activity: NeuraCompanionActivity.present));

  /// Leaves the suite: the stage goes back to the defaults every other room
  /// uses, and later calls do nothing.
  void close() {
    if (_closed) return;
    _stage = NeuraStagePresentation.defaults;
    _publish(_stage);
    _closed = true;
  }

  void _set(NeuraStagePresentation next) {
    if (_closed || next == _stage) return;
    _stage = next;
    _publish(next);
    notifyListeners();
  }

  void _onSafeMode() {
    if (_safeMode.value && resting) wake();
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _safeMode.removeListener(_onSafeMode);
    close();
    super.dispose();
  }
}
