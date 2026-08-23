import 'package:flutter/foundation.dart';

import 'neura_adaptive_intent_controller.dart';
import 'neura_adaptive_outcome_loop.dart';
import 'neura_adaptive_plan_session.dart';

typedef NeuraAdaptiveRuntimeClock = DateTime Function();

class NeuraAdaptiveIntentRuntime extends ChangeNotifier {
  NeuraAdaptiveIntentRuntime({
    required this.controller,
    NeuraAdaptiveOutcomeLoop outcomeLoop = const NeuraAdaptiveOutcomeLoop(),
    NeuraAdaptiveRuntimeClock? clock,
    int maxOutcomeHistory = 20,
  }) : outcomeLoop = outcomeLoop,
       _clock = clock ?? DateTime.now,
       _maxOutcomeHistory = maxOutcomeHistory.clamp(1, 100).toInt();

  static final NeuraAdaptiveIntentRuntime instance =
      NeuraAdaptiveIntentRuntime(
        controller: NeuraAdaptiveIntentController.instance,
      );

  final NeuraAdaptiveIntentController controller;
  final NeuraAdaptiveOutcomeLoop outcomeLoop;
  final NeuraAdaptiveRuntimeClock _clock;
  final int _maxOutcomeHistory;

  NeuraAdaptivePlanSession? _session;
  NeuraPlanOutcomeReceipt? _lastOutcome;
  NeuraOutcomeAdaptation? _lastAdaptation;
  final List<NeuraPlanOutcomeReceipt> _outcomes =
      <NeuraPlanOutcomeReceipt>[];

  NeuraAdaptivePlanSession? get session => _session;
  NeuraPlanOutcomeReceipt? get lastOutcome => _lastOutcome;
  NeuraOutcomeAdaptation? get lastAdaptation => _lastAdaptation;
  List<NeuraPlanOutcomeReceipt> get outcomes =>
      List<NeuraPlanOutcomeReceipt>.unmodifiable(_outcomes);

  Future<NeuraAdaptivePlanSession> startSession(
    String outcome, {
    DateTime? now,
  }) async {
    final current = _session;
    if (current != null &&
        current.status == NeuraPlanSessionStatus.active) {
      throw StateError('Finish or discard the active Adaptive Intent session.');
    }
    await controller.initialize();
    if (controller.safeMode) {
      throw StateError('Safe Mode blocks active Adaptive Intent sessions.');
    }

    final startedAt = (now ?? _clock()).toUtc();
    final graph = controller.compileOutcome(outcome, now: startedAt);
    final next = NeuraAdaptivePlanSession.start(
      graph,
      startedAt: startedAt,
    );
    _session = next;
    notifyListeners();
    return next;
  }

  void completeStep(
    String stepId, {
    required bool userGesture,
    bool approvalGranted = false,
    DateTime? at,
  }) {
    final current = _requireSession();
    current.completeStep(
      stepId,
      userGesture: userGesture,
      approvalGranted: approvalGranted,
      safeMode: controller.safeMode,
      at: at ?? _clock(),
    );
    notifyListeners();
  }

  void deferStep(
    String stepId, {
    required bool userGesture,
    DateTime? at,
  }) {
    final current = _requireSession();
    current.deferStep(
      stepId,
      userGesture: userGesture,
      safeMode: controller.safeMode,
      at: at ?? _clock(),
    );
    notifyListeners();
  }

  void resumeStep(
    String stepId, {
    required bool userGesture,
    DateTime? at,
  }) {
    final current = _requireSession();
    current.resumeStep(
      stepId,
      userGesture: userGesture,
      safeMode: controller.safeMode,
      at: at ?? _clock(),
    );
    notifyListeners();
  }

  NeuraPlanOutcomeReceipt finishSession({
    required bool userGesture,
    bool abandoned = false,
    double perceivedEffort = 0.5,
    double satisfaction = 0.5,
    int interruptionCount = 0,
    DateTime? endedAt,
  }) {
    if (controller.safeMode) {
      throw StateError('Safe Mode blocks Adaptive Intent outcome changes.');
    }
    final current = _requireSession();
    final outcome = current.finish(
      userGesture: userGesture,
      abandoned: abandoned,
      perceivedEffort: perceivedEffort,
      satisfaction: satisfaction,
      interruptionCount: interruptionCount,
      endedAt: endedAt ?? _clock(),
    );
    _lastOutcome = outcome;
    _outcomes.add(outcome);
    if (_outcomes.length > _maxOutcomeHistory) {
      _outcomes.removeRange(0, _outcomes.length - _maxOutcomeHistory);
    }
    _lastAdaptation = outcomeLoop.evaluate(
      history: _outcomes,
      currentState: controller.state,
    );
    _session = null;
    controller.clearPlan();
    notifyListeners();
    return outcome;
  }

  void discardSession({required bool userGesture}) {
    if (!userGesture) {
      throw StateError('Discarding a plan requires a direct user gesture.');
    }
    if (_session == null) return;
    _session = null;
    controller.clearPlan();
    notifyListeners();
  }

  void resetAfterDataWipe() {
    _session = null;
    _lastOutcome = null;
    _lastAdaptation = null;
    _outcomes.clear();
    controller.clearPlan();
    notifyListeners();
  }

  NeuraAdaptivePlanSession _requireSession() {
    final current = _session;
    if (current == null) {
      throw StateError('No Adaptive Intent session is active.');
    }
    return current;
  }
}
