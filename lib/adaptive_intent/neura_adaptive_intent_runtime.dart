import 'dart:async';

import 'package:flutter/foundation.dart';

import 'neura_adaptive_intent_controller.dart';
import 'neura_adaptive_intent_preferences.dart';
import 'neura_adaptive_outcome_loop.dart';
import 'neura_adaptive_plan_session.dart';
import 'neura_live_signal_adapter.dart';
import 'neura_outcome_store.dart';

typedef NeuraAdaptiveRuntimeClock = DateTime Function();

class NeuraAdaptiveIntentRuntime extends ChangeNotifier {
  NeuraAdaptiveIntentRuntime({
    required this.controller,
    this.outcomeLoop = const NeuraAdaptiveOutcomeLoop(),
    NeuraOutcomeStore? outcomeStore,
    NeuraAdaptiveIntentPreferencesController? preferencesController,
    NeuraLiveSignalAdapter? liveSignalAdapter,
    NeuraAdaptiveRuntimeClock? clock,
    int maxOutcomeHistory = 100,
  })  : _outcomeStore = outcomeStore,
        _preferencesController = preferencesController,
        _liveSignalAdapter = liveSignalAdapter,
        _clock = clock ?? DateTime.now,
        _maxOutcomeHistory = maxOutcomeHistory.clamp(1, 500).toInt();

  static final NeuraAdaptiveIntentRuntime instance = NeuraAdaptiveIntentRuntime(
    controller: NeuraAdaptiveIntentController.instance,
    outcomeStore: NeuraEncryptedOutcomeStore(),
    preferencesController: NeuraAdaptiveIntentPreferencesController.instance,
    liveSignalAdapter: NeuraLiveSignalAdapter.instance,
  );

  final NeuraAdaptiveIntentController controller;
  final NeuraAdaptiveOutcomeLoop outcomeLoop;
  final NeuraOutcomeStore? _outcomeStore;
  final NeuraAdaptiveIntentPreferencesController? _preferencesController;
  final NeuraLiveSignalAdapter? _liveSignalAdapter;
  final NeuraAdaptiveRuntimeClock _clock;
  final int _maxOutcomeHistory;

  NeuraAdaptivePlanSession? _session;
  NeuraPlanOutcomeReceipt? _lastOutcome;
  NeuraOutcomeAdaptation? _lastAdaptation;
  NeuraLiveSignalSnapshot? _lastLiveSignals;
  final List<NeuraPlanOutcomeReceipt> _outcomes = <NeuraPlanOutcomeReceipt>[];

  bool _initialized = false;
  bool _disposed = false;
  bool _writesSuspended = false;
  int _dataGeneration = 0;
  Future<void>? _initializeFuture;
  Future<void> _writeQueue = Future<void>.value();
  Object? _lastPersistenceError;
  Object? _lastSignalError;

  NeuraAdaptivePlanSession? get session => _session;
  NeuraPlanOutcomeReceipt? get lastOutcome => _lastOutcome;
  NeuraOutcomeAdaptation? get lastAdaptation => _lastAdaptation;
  NeuraLiveSignalSnapshot? get lastLiveSignals => _lastLiveSignals;
  List<NeuraPlanOutcomeReceipt> get outcomes =>
      List<NeuraPlanOutcomeReceipt>.unmodifiable(_outcomes);
  NeuraAdaptiveIntentPreferencesController? get preferencesController =>
      _preferencesController;
  bool get featureEnabled => _preferencesController?.enabled ?? true;
  bool get initialized => _initialized;
  Object? get lastPersistenceError => _lastPersistenceError;
  Object? get lastSignalError => _lastSignalError;

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    final existing = _initializeFuture;
    if (existing != null) return existing;

    late final Future<void> attempt;
    attempt = _initialize().whenComplete(() {
      if (identical(_initializeFuture, attempt)) {
        _initializeFuture = null;
      }
    });
    _initializeFuture = attempt;
    return attempt;
  }

  Future<void> _initialize() async {
    if (_writesSuspended) {
      throw StateError(
        'Adaptive Intent is suspended during local-data removal.',
      );
    }

    await controller.initialize();
    await _preferencesController?.initialize();

    final store = _outcomeStore;
    if (store != null) {
      try {
        final restored = await store.load();
        _outcomes
          ..clear()
          ..addAll(restored);
        _trimOutcomes();
        _lastOutcome = _outcomes.isEmpty ? null : _outcomes.last;
        _lastPersistenceError = null;
      } catch (error) {
        _outcomes.clear();
        _lastOutcome = null;
        _lastPersistenceError = error;
      }
    }

    if (_outcomes.isNotEmpty) {
      _lastAdaptation = outcomeLoop.evaluate(
        history: _outcomes,
        currentState: controller.state,
      );
    }

    if (featureEnabled && _liveSignalAdapter != null) {
      try {
        await _refreshLiveSignals();
      } catch (error) {
        _lastSignalError = error;
      }
    }

    _initialized = true;
    if (!_disposed) notifyListeners();
  }

  Future<NeuraLiveSignalSnapshot?> refreshLiveSignals() async {
    await initialize();
    if (!featureEnabled || _liveSignalAdapter == null) return null;
    return _refreshLiveSignals();
  }

  Future<NeuraLiveSignalSnapshot> _refreshLiveSignals() async {
    final adapter = _liveSignalAdapter;
    if (adapter == null) {
      throw StateError('No Adaptive Intent live-signal adapter is available.');
    }
    final policy = _preferencesController?.preferences.signalPolicy ??
        const NeuraLiveSignalSourcePolicy();
    final snapshot = await adapter.collect(
      baseline: controller.signals,
      policy: policy,
    );
    if (_writesSuspended) {
      throw StateError(
        'Adaptive Intent signals were invalidated by local-data removal.',
      );
    }
    controller.updateSignals(
      energy: snapshot.signals.energy,
      focus: snapshot.signals.focus,
      cognitiveLoad: snapshot.signals.cognitiveLoad,
      urgency: snapshot.signals.urgency,
      taskSwitchRate: snapshot.signals.taskSwitchRate,
      completionRate: snapshot.signals.completionRate,
      notificationPressure: snapshot.signals.notificationPressure,
      evidenceCount: snapshot.signals.evidenceCount,
      includesSelfReport: snapshot.signals.includesSelfReport,
    );
    _lastLiveSignals = snapshot;
    _lastSignalError = null;
    if (!_disposed) notifyListeners();
    return snapshot;
  }

  Future<NeuraAdaptivePlanSession> startSession(
    String outcome, {
    DateTime? now,
  }) async {
    await initialize();
    if (!featureEnabled) {
      throw StateError(
        'Adaptive Intent must be enabled before starting a session.',
      );
    }
    if (_writesSuspended) {
      throw StateError(
        'Adaptive Intent is suspended during local-data removal.',
      );
    }
    final current = _session;
    if (current != null && current.status == NeuraPlanSessionStatus.active) {
      throw StateError(
        'Finish or discard the active Adaptive Intent session.',
      );
    }
    if (controller.safeMode) {
      throw StateError('Safe Mode blocks active Adaptive Intent sessions.');
    }

    if (_liveSignalAdapter != null) {
      try {
        await _refreshLiveSignals();
      } catch (error) {
        _lastSignalError = error;
      }
    }

    final startedAt = (now ?? _clock()).toUtc();
    final graph = controller.compileOutcome(outcome, now: startedAt);
    final next = NeuraAdaptivePlanSession.start(
      graph,
      startedAt: startedAt,
    );
    _session = next;
    recordSurfaceVisit('adaptive_session');
    if (!_disposed) notifyListeners();
    return next;
  }

  void completeStep(
    String stepId, {
    required bool userGesture,
    bool approvalGranted = false,
    DateTime? at,
  }) {
    _requireFeatureEnabled();
    final current = _requireSession();
    current.completeStep(
      stepId,
      userGesture: userGesture,
      approvalGranted: approvalGranted,
      safeMode: controller.safeMode,
      at: at ?? _clock(),
    );
    if (!_disposed) notifyListeners();
  }

  void deferStep(
    String stepId, {
    required bool userGesture,
    DateTime? at,
  }) {
    _requireFeatureEnabled();
    final current = _requireSession();
    current.deferStep(
      stepId,
      userGesture: userGesture,
      safeMode: controller.safeMode,
      at: at ?? _clock(),
    );
    if (!_disposed) notifyListeners();
  }

  void resumeStep(
    String stepId, {
    required bool userGesture,
    DateTime? at,
  }) {
    _requireFeatureEnabled();
    final current = _requireSession();
    current.resumeStep(
      stepId,
      userGesture: userGesture,
      safeMode: controller.safeMode,
      at: at ?? _clock(),
    );
    if (!_disposed) notifyListeners();
  }

  NeuraPlanOutcomeReceipt finishSession({
    required bool userGesture,
    bool abandoned = false,
    double perceivedEffort = 0.5,
    double satisfaction = 0.5,
    int interruptionCount = 0,
    DateTime? endedAt,
  }) {
    _requireFeatureEnabled();
    if (_writesSuspended) {
      throw StateError(
        'Adaptive Intent is suspended during local-data removal.',
      );
    }
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
    _trimOutcomes();
    _lastAdaptation = outcomeLoop.evaluate(
      history: _outcomes,
      currentState: controller.state,
    );
    _session = null;
    controller.clearPlan();
    _enqueueOutcomePersist();
    if (!_disposed) notifyListeners();
    return outcome;
  }

  Future<NeuraPlanOutcomeReceipt> finishSessionAndPersist({
    required bool userGesture,
    bool abandoned = false,
    double perceivedEffort = 0.5,
    double satisfaction = 0.5,
    int interruptionCount = 0,
    DateTime? endedAt,
  }) async {
    final outcome = finishSession(
      userGesture: userGesture,
      abandoned: abandoned,
      perceivedEffort: perceivedEffort,
      satisfaction: satisfaction,
      interruptionCount: interruptionCount,
      endedAt: endedAt,
    );
    await flush();
    return outcome;
  }

  void discardSession({required bool userGesture}) {
    if (!userGesture) {
      throw StateError(
        'Discarding a plan requires a direct user gesture.',
      );
    }
    if (_session == null) return;
    _session = null;
    controller.clearPlan();
    if (!_disposed) notifyListeners();
  }

  void recordSurfaceVisit(String surfaceId, {DateTime? at}) {
    _liveSignalAdapter?.activityTracker.recordSurfaceVisit(
      surfaceId,
      at: at,
    );
  }

  void recordInterruption({DateTime? at}) {
    _liveSignalAdapter?.activityTracker.recordInterruption(at: at);
  }

  Future<void> flush() => _writeQueue;

  void _enqueueOutcomePersist() {
    final store = _outcomeStore;
    if (store == null || _writesSuspended) return;
    final generation = _dataGeneration;
    final snapshot = List<NeuraPlanOutcomeReceipt>.unmodifiable(_outcomes);
    final previous = _writeQueue;
    final operation = _persistAfter(
      previous: previous,
      store: store,
      outcomes: snapshot,
      generation: generation,
    );
    _writeQueue = operation.then<void>((_) {}, onError: (_) {});
  }

  Future<void> _persistAfter({
    required Future<void> previous,
    required NeuraOutcomeStore store,
    required List<NeuraPlanOutcomeReceipt> outcomes,
    required int generation,
  }) async {
    try {
      await previous;
    } catch (_) {}
    if (!_isCurrent(generation)) return;

    try {
      await store.save(outcomes);
      if (!_isCurrent(generation)) return;
      final hadError = _lastPersistenceError != null;
      _lastPersistenceError = null;
      if (hadError && !_disposed) notifyListeners();
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _lastPersistenceError = error;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _dataGeneration += 1;
    Object? drainFailure;
    try {
      await _writeQueue.timeout(const Duration(seconds: 3));
    } catch (error) {
      drainFailure = error;
    }

    Object? clearFailure;
    try {
      await _outcomeStore?.clear();
      await _preferencesController?.resetAfterDataWipe();
      await controller.resetPersistedState();
    } catch (error) {
      clearFailure = error;
    }

    _liveSignalAdapter?.activityTracker.resetAfterDataWipe();
    _session = null;
    _lastOutcome = null;
    _lastAdaptation = null;
    _lastLiveSignals = null;
    _outcomes.clear();
    _lastPersistenceError = null;
    _lastSignalError = null;
    _initialized = false;
    _initializeFuture = null;
    _writeQueue = Future<void>.value();
    if (!_disposed) notifyListeners();

    if (drainFailure != null || clearFailure != null) {
      throw StateError(
        'Adaptive Intent local-data shutdown could not be verified.',
      );
    }
  }

  void resumeAfterDataWipe() {
    _writesSuspended = false;
    _preferencesController?.resumeAfterDataWipe();
  }

  void _trimOutcomes() {
    if (_outcomes.length > _maxOutcomeHistory) {
      _outcomes.removeRange(
        0,
        _outcomes.length - _maxOutcomeHistory,
      );
    }
  }

  bool _isCurrent(int generation) =>
      !_writesSuspended && generation == _dataGeneration;

  void _requireFeatureEnabled() {
    if (!featureEnabled) {
      throw StateError(
        'Adaptive Intent is disabled and cannot change plan authority.',
      );
    }
  }

  NeuraAdaptivePlanSession _requireSession() {
    final current = _session;
    if (current == null) {
      throw StateError('No Adaptive Intent session is active.');
    }
    return current;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
