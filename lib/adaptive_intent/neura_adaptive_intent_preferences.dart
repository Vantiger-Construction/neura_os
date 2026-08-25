import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../startup/neura_prefs_cache.dart';
import 'neura_live_signal_adapter.dart';

class NeuraAdaptiveIntentPreferences {
  const NeuraAdaptiveIntentPreferences({
    this.enabled = false,
    this.onboardingComplete = false,
    this.useMoodSignal = true,
    this.useFocusSignal = true,
    this.useQuestSignal = true,
    this.useActivitySignal = true,
  });

  final bool enabled;
  final bool onboardingComplete;
  final bool useMoodSignal;
  final bool useFocusSignal;
  final bool useQuestSignal;
  final bool useActivitySignal;

  NeuraLiveSignalSourcePolicy get signalPolicy {
    return NeuraLiveSignalSourcePolicy(
      useMood: useMoodSignal,
      useFocus: useFocusSignal,
      useQuests: useQuestSignal,
      useActivity: useActivitySignal,
    );
  }

  NeuraAdaptiveIntentPreferences copyWith({
    bool? enabled,
    bool? onboardingComplete,
    bool? useMoodSignal,
    bool? useFocusSignal,
    bool? useQuestSignal,
    bool? useActivitySignal,
  }) {
    return NeuraAdaptiveIntentPreferences(
      enabled: enabled ?? this.enabled,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      useMoodSignal: useMoodSignal ?? this.useMoodSignal,
      useFocusSignal: useFocusSignal ?? this.useFocusSignal,
      useQuestSignal: useQuestSignal ?? this.useQuestSignal,
      useActivitySignal: useActivitySignal ?? this.useActivitySignal,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'v': 1,
      'enabled': enabled,
      'onboarding_complete': onboardingComplete,
      'use_mood_signal': useMoodSignal,
      'use_focus_signal': useFocusSignal,
      'use_quest_signal': useQuestSignal,
      'use_activity_signal': useActivitySignal,
    };
  }

  factory NeuraAdaptiveIntentPreferences.fromJson(
    Map<String, Object?> json,
  ) {
    return NeuraAdaptiveIntentPreferences(
      enabled: json['enabled'] == true,
      onboardingComplete: json['onboarding_complete'] == true,
      useMoodSignal: json['use_mood_signal'] != false,
      useFocusSignal: json['use_focus_signal'] != false,
      useQuestSignal: json['use_quest_signal'] != false,
      useActivitySignal: json['use_activity_signal'] != false,
    );
  }
}

abstract interface class NeuraAdaptiveIntentPreferencesStore {
  Future<NeuraAdaptiveIntentPreferences?> load();

  Future<void> save(NeuraAdaptiveIntentPreferences preferences);

  Future<void> clear();
}

class NeuraPrefsAdaptiveIntentPreferencesStore
    implements NeuraAdaptiveIntentPreferencesStore {
  const NeuraPrefsAdaptiveIntentPreferencesStore();

  static const stateKey = 'neura.adaptive_intent.enrollment.v1';

  @override
  Future<NeuraAdaptiveIntentPreferences?> load() async {
    final raw = NeuraPrefsCache.prefs.getString(stateKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return NeuraAdaptiveIntentPreferences.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(NeuraAdaptiveIntentPreferences preferences) async {
    final written = await NeuraPrefsCache.prefs.setString(
      stateKey,
      jsonEncode(preferences.toJson()),
    );
    if (!written) {
      throw StateError('Adaptive Intent enrollment could not be saved.');
    }
  }

  @override
  Future<void> clear() async {
    await NeuraPrefsCache.prefs.remove(stateKey);
  }
}

class NeuraAdaptiveIntentPreferencesController extends ChangeNotifier {
  NeuraAdaptiveIntentPreferencesController({
    NeuraAdaptiveIntentPreferencesStore? store,
    NeuraAdaptiveIntentPreferences initial =
        const NeuraAdaptiveIntentPreferences(),
  })  : _store = store,
        _preferences = initial,
        _initialized = store == null;

  static final NeuraAdaptiveIntentPreferencesController instance =
      NeuraAdaptiveIntentPreferencesController(
    store: const NeuraPrefsAdaptiveIntentPreferencesStore(),
  );

  final NeuraAdaptiveIntentPreferencesStore? _store;

  NeuraAdaptiveIntentPreferences _preferences;
  bool _initialized;
  bool _writesSuspended = false;
  bool _disposed = false;
  Future<void>? _initializeFuture;
  Future<void> _writeQueue = Future<void>.value();
  Object? _lastError;

  NeuraAdaptiveIntentPreferences get preferences => _preferences;
  bool get enabled => _preferences.enabled && _preferences.onboardingComplete;
  bool get initialized => _initialized;
  Object? get lastError => _lastError;

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
        'Adaptive Intent enrollment is suspended during data removal.',
      );
    }
    final loaded = await _store?.load();
    if (loaded != null) {
      _preferences = loaded;
    }
    _initialized = true;
    _lastError = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> completeOnboarding({
    required bool useMoodSignal,
    required bool useFocusSignal,
    required bool useQuestSignal,
    required bool useActivitySignal,
  }) {
    return update(
      _preferences.copyWith(
        enabled: true,
        onboardingComplete: true,
        useMoodSignal: useMoodSignal,
        useFocusSignal: useFocusSignal,
        useQuestSignal: useQuestSignal,
        useActivitySignal: useActivitySignal,
      ),
    );
  }

  Future<void> setEnabled(bool value) {
    return update(
      _preferences.copyWith(
        enabled: value,
        onboardingComplete: value ? true : _preferences.onboardingComplete,
      ),
    );
  }

  Future<void> updateSources({
    bool? useMoodSignal,
    bool? useFocusSignal,
    bool? useQuestSignal,
    bool? useActivitySignal,
  }) {
    return update(
      _preferences.copyWith(
        useMoodSignal: useMoodSignal,
        useFocusSignal: useFocusSignal,
        useQuestSignal: useQuestSignal,
        useActivitySignal: useActivitySignal,
      ),
    );
  }

  Future<void> update(NeuraAdaptiveIntentPreferences next) async {
    await initialize();
    if (_writesSuspended) {
      throw StateError(
        'Adaptive Intent enrollment is suspended during data removal.',
      );
    }

    final previous = _writeQueue;
    final operation = _persistAfter(previous, next);
    _writeQueue = operation.then<void>((_) {}, onError: (_) {});
    await operation;
  }

  Future<void> _persistAfter(
    Future<void> previous,
    NeuraAdaptiveIntentPreferences next,
  ) async {
    try {
      await previous;
    } catch (_) {
      // A later valid choice may recover after a previous failed write.
    }

    try {
      await _store?.save(next);
      // A data wipe waits for this queue and clears the backing store after it
      // drains. Do not let a write that started before suspension re-enable the
      // in-memory feature while that wipe is completing.
      if (_writesSuspended) return;
      _preferences = next;
      _lastError = null;
      if (!_disposed) notifyListeners();
    } catch (error, stackTrace) {
      _lastError = error;
      if (!_disposed) notifyListeners();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _preferences = const NeuraAdaptiveIntentPreferences();
    if (!_disposed) notifyListeners();

    Object? drainFailure;
    try {
      await _writeQueue.timeout(const Duration(seconds: 3));
    } catch (error) {
      drainFailure = error;
    }

    Object? clearFailure;
    try {
      await _store?.clear();
    } catch (error) {
      clearFailure = error;
    }

    // Reassert the disabled defaults after draining because a save that was
    // already in flight may have completed while suspension was being latched.
    _preferences = const NeuraAdaptiveIntentPreferences();
    _initialized = _store == null;
    _initializeFuture = null;
    _writeQueue = Future<void>.value();
    _lastError = null;
    if (drainFailure != null || clearFailure != null) {
      throw StateError(
        'Adaptive Intent enrollment shutdown could not be verified.',
      );
    }
  }

  void resumeAfterDataWipe() {
    _writesSuspended = false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
