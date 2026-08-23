import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cognitive/neura_bandwidth_engine.dart';
import '../cognitive/neura_cognitive_state.dart';
import '../cognitive/neura_interface_policy.dart';
import '../constitution/neura_personal_constitution.dart';
import '../intent_compiler/neura_action_graph.dart';
import '../intent_compiler/neura_intent_compiler.dart';
import '../reliability/safe_boot.dart';
import 'neura_adaptive_intent_store.dart';

typedef NeuraAdaptiveIntentClock = DateTime Function();

class NeuraAdaptiveIntentController extends ChangeNotifier {
  NeuraAdaptiveIntentController({
    NeuraBandwidthEngine bandwidthEngine = const NeuraBandwidthEngine(),
    NeuraIntentCompiler intentCompiler = const NeuraIntentCompiler(),
    NeuraCognitiveSignals? signals,
    NeuraPersonalConstitution constitution = const NeuraPersonalConstitution(),
    bool? safeMode,
    ValueListenable<bool>? safeModeListenable,
    NeuraAdaptiveIntentStore? store,
    NeuraAdaptiveIntentClock? clock,
    Duration signalMaxAge = const Duration(hours: 12),
    Duration persistDelay = const Duration(milliseconds: 250),
  })  : bandwidthEngine = bandwidthEngine,
        intentCompiler = intentCompiler,
        _signals = (signals ?? NeuraCognitiveSignals.defaults()).normalized(),
        _constitution = constitution.normalized(),
        _safeModeListenable = safeModeListenable,
        _safeMode = safeMode ?? safeModeListenable?.value ?? false,
        _store = store,
        _clock = clock ?? DateTime.now,
        _signalMaxAge = signalMaxAge,
        _persistDelay = persistDelay,
        _initialized = store == null {
    _recalculate();
  }

  static final NeuraAdaptiveIntentController instance =
      NeuraAdaptiveIntentController(
    store: const NeuraPrefsAdaptiveIntentStore(),
    safeModeListenable: SafeBoot.instance.safeMode,
  );

  final NeuraBandwidthEngine bandwidthEngine;
  final NeuraIntentCompiler intentCompiler;
  final ValueListenable<bool>? _safeModeListenable;
  final NeuraAdaptiveIntentStore? _store;
  final NeuraAdaptiveIntentClock _clock;
  final Duration _signalMaxAge;
  final Duration _persistDelay;

  NeuraCognitiveSignals _signals;
  NeuraPersonalConstitution _constitution;
  late NeuraCognitiveState _state;
  late NeuraInterfacePolicy _interfacePolicy;
  NeuraActionGraph? _plan;
  bool _safeMode;
  bool _initialized;
  bool _safeModeListenerAttached = false;
  bool _disposed = false;
  Future<void>? _initializeFuture;
  Future<void> _writeQueue = Future<void>.value();
  Timer? _persistTimer;
  Object? _lastPersistenceError;

  NeuraCognitiveSignals get signals => _signals;
  NeuraPersonalConstitution get constitution => _constitution;
  NeuraCognitiveState get state => _state;
  NeuraInterfacePolicy get interfacePolicy => _interfacePolicy;
  NeuraActionGraph? get plan => _plan;
  bool get safeMode => _safeMode;
  bool get initialized => _initialized;
  Object? get lastPersistenceError => _lastPersistenceError;

  Future<void> initialize() {
    if (_initialized) {
      _attachSafeModeListener();
      final source = _safeModeListenable;
      if (source != null) {
        setSafeMode(source.value);
      }
      return Future<void>.value();
    }
    final existing = _initializeFuture;
    if (existing != null) return existing;

    final attempt = _initializeWithRetryReset();
    _initializeFuture = attempt;
    return attempt;
  }

  Future<void> _initializeWithRetryReset() async {
    try {
      await _initialize();
    } catch (error, stackTrace) {
      _initializeFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _initialize() async {
    _attachSafeModeListener();
    final store = _store;
    if (store != null) {
      final snapshot = await store.load();
      if (snapshot != null) {
        _constitution = snapshot.constitution.normalized();
        if (snapshot.hasFreshSignalsAt(_clock(), maxAge: _signalMaxAge)) {
          _signals = snapshot.signals.normalized();
        }
      }
    }
    final source = _safeModeListenable;
    if (source != null) {
      _safeMode = source.value;
    }
    _recalculate();
    _initialized = true;
    _initializeFuture = null;
    notifyListeners();
  }

  void updateSignals({
    double? energy,
    double? focus,
    double? cognitiveLoad,
    double? urgency,
    double? taskSwitchRate,
    double? completionRate,
    double? notificationPressure,
  }) {
    _requireReady();
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
    _schedulePersist();
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
    _requireReady();
    if (identical(value, _constitution)) return;
    _constitution = value.normalized();
    _plan = null;
    _schedulePersist();
    notifyListeners();
  }

  NeuraActionGraph compileOutcome(String outcome, {DateTime? now}) {
    _requireReady();
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

  Future<void> flush() async {
    if (_persistTimer != null) {
      _enqueuePersist();
    }
    await _writeQueue;
  }

  Future<void> resetPersistedState() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _writeQueue;
    await _store?.clear();
    _signals = NeuraCognitiveSignals.defaults();
    _constitution = const NeuraPersonalConstitution();
    _plan = null;
    _lastPersistenceError = null;
    _recalculate();
    notifyListeners();
  }

  void _attachSafeModeListener() {
    final source = _safeModeListenable;
    if (source == null || _safeModeListenerAttached) return;
    source.addListener(_onSafeModeChanged);
    _safeModeListenerAttached = true;
  }

  void _onSafeModeChanged() {
    final source = _safeModeListenable;
    if (source != null) {
      setSafeMode(source.value);
    }
  }

  void _schedulePersist() {
    if (_store == null || !_initialized) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDelay, _enqueuePersist);
  }

  void _enqueuePersist() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final store = _store;
    if (store == null || !_initialized) return;
    final snapshot = NeuraAdaptiveIntentSnapshot(
      signals: _signals,
      constitution: _constitution,
      savedAt: _clock().toUtc(),
    );
    _writeQueue = _persistAfter(
      previous: _writeQueue,
      store: store,
      snapshot: snapshot,
    );
  }

  Future<void> _persistAfter({
    required Future<void> previous,
    required NeuraAdaptiveIntentStore store,
    required NeuraAdaptiveIntentSnapshot snapshot,
  }) async {
    try {
      await previous;
    } catch (_) {
      // A later valid snapshot is still allowed to recover after a failed write.
    }
    try {
      await store.save(snapshot);
      final hadError = _lastPersistenceError != null;
      _lastPersistenceError = null;
      if (hadError && !_disposed) {
        notifyListeners();
      }
    } catch (error) {
      final changed = !identical(_lastPersistenceError, error);
      _lastPersistenceError = error;
      if (changed && !_disposed) {
        notifyListeners();
      }
    }
  }

  void _requireReady() {
    if (_store != null && !_initialized) {
      throw StateError(
        'Adaptive Intent must finish initialize() before it can be changed.',
      );
    }
  }

  void _recalculate() {
    _state = bandwidthEngine.estimate(_signals, safeMode: _safeMode);
    _interfacePolicy = NeuraInterfacePolicy.forState(
      _state,
      safeMode: _safeMode,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    final source = _safeModeListenable;
    if (source != null && _safeModeListenerAttached) {
      source.removeListener(_onSafeModeChanged);
      _safeModeListenerAttached = false;
    }
    super.dispose();
  }
}
