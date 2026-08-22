import 'package:flutter/foundation.dart';

import '../cognitive/neura_bandwidth_engine.dart';
import '../cognitive/neura_cognitive_state.dart';
import '../cognitive/neura_interface_policy.dart';
import '../constitution/neura_personal_constitution.dart';
import '../intent_compiler/neura_action_graph.dart';
import '../intent_compiler/neura_intent_compiler.dart';

class NeuraAdaptiveIntentController extends ChangeNotifier {
  final NeuraBandwidthEngine bandwidthEngine;
  final NeuraIntentCompiler intentCompiler;

  NeuraCognitiveSignals _signals;
  NeuraPersonalConstitution _constitution;
  late NeuraCognitiveState _state;
  late NeuraInterfacePolicy _interfacePolicy;
  NeuraActionGraph? _plan;
  bool _safeMode;

  NeuraAdaptiveIntentController({
    NeuraBandwidthEngine bandwidthEngine = const NeuraBandwidthEngine(),
    NeuraIntentCompiler intentCompiler = const NeuraIntentCompiler(),
    NeuraCognitiveSignals? signals,
    NeuraPersonalConstitution constitution =
        const NeuraPersonalConstitution(),
    bool safeMode = false,
  })  : bandwidthEngine = bandwidthEngine,
        intentCompiler = intentCompiler,
        _signals = signals ?? NeuraCognitiveSignals.defaults(),
        _constitution = constitution,
        _safeMode = safeMode {
    _recalculate();
  }

  NeuraCognitiveSignals get signals => _signals;
  NeuraPersonalConstitution get constitution => _constitution;
  NeuraCognitiveState get state => _state;
  NeuraInterfacePolicy get interfacePolicy => _interfacePolicy;
  NeuraActionGraph? get plan => _plan;
  bool get safeMode => _safeMode;

  void updateSignals({
    double? energy,
    double? focus,
    double? cognitiveLoad,
    double? urgency,
    double? taskSwitchRate,
    double? completionRate,
    double? notificationPressure,
  }) {
    _signals = _signals.copyWith(
      energy: energy,
      focus: focus,
      cognitiveLoad: cognitiveLoad,
      urgency: urgency,
      taskSwitchRate: taskSwitchRate,
      completionRate: completionRate,
      notificationPressure: notificationPressure,
    );
    _plan = null;
    _recalculate();
    notifyListeners();
  }

  void setSafeMode(bool value) {
    if (_safeMode == value) return;
    _safeMode = value;
    _plan = null;
    _recalculate();
    notifyListeners();
  }

  void updateConstitution(NeuraPersonalConstitution value) {
    if (identical(value, _constitution)) return;
    _constitution = value;
    _plan = null;
    notifyListeners();
  }

  NeuraActionGraph compileOutcome(
    String outcome, {
    DateTime? now,
  }) {
    _plan = intentCompiler.compile(
      outcome: outcome,
      cognitiveState: _state,
      interfacePolicy: _interfacePolicy,
      constitution: _constitution,
      safeMode: _safeMode,
      now: now,
    );
    notifyListeners();
    return _plan!;
  }

  void clearPlan() {
    if (_plan == null) return;
    _plan = null;
    notifyListeners();
  }

  void _recalculate() {
    _state = bandwidthEngine.estimate(_signals, safeMode: _safeMode);
    _interfacePolicy = NeuraInterfacePolicy.forState(
      _state,
      safeMode: _safeMode,
    );
  }
}
