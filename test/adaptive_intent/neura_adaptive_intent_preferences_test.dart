import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_preferences.dart';

void main() {
  test('Adaptive Intent stays disabled until onboarding is completed',
      () async {
    final store = _MemoryPreferencesStore();
    final controller = NeuraAdaptiveIntentPreferencesController(store: store);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.enabled, isFalse);

    await controller.completeOnboarding(
      useMoodSignal: true,
      useFocusSignal: true,
      useQuestSignal: false,
      useActivitySignal: true,
    );

    expect(controller.enabled, isTrue);
    expect(controller.preferences.useQuestSignal, isFalse);

    final restored = NeuraAdaptiveIntentPreferencesController(store: store);
    addTearDown(restored.dispose);
    await restored.initialize();

    expect(restored.enabled, isTrue);
    expect(restored.preferences.useQuestSignal, isFalse);
  });

  test('data wipe clears enrollment and leaves the gate closed', () async {
    final store = _MemoryPreferencesStore();
    final controller = NeuraAdaptiveIntentPreferencesController(store: store);
    addTearDown(controller.dispose);

    await controller.completeOnboarding(
      useMoodSignal: true,
      useFocusSignal: true,
      useQuestSignal: true,
      useActivitySignal: true,
    );
    expect(controller.enabled, isTrue);

    await controller.resetAfterDataWipe();

    expect(controller.enabled, isFalse);
    expect(store.value, isNull);
  });

  test('data wipe wins over an in-flight enrollment write', () async {
    final store = _BlockingPreferencesStore();
    final controller = NeuraAdaptiveIntentPreferencesController(store: store);
    addTearDown(controller.dispose);

    final update = controller.completeOnboarding(
      useMoodSignal: true,
      useFocusSignal: true,
      useQuestSignal: true,
      useActivitySignal: true,
    );
    await store.saveStarted.future;

    final wipe = controller.resetAfterDataWipe();
    store.release();

    await update;
    await wipe;

    expect(controller.enabled, isFalse);
    expect(controller.preferences.onboardingComplete, isFalse);
    expect(store.value, isNull);
  });
}

class _MemoryPreferencesStore implements NeuraAdaptiveIntentPreferencesStore {
  NeuraAdaptiveIntentPreferences? value;

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<NeuraAdaptiveIntentPreferences?> load() async => value;

  @override
  Future<void> save(NeuraAdaptiveIntentPreferences preferences) async {
    value = preferences;
  }
}

class _BlockingPreferencesStore implements NeuraAdaptiveIntentPreferencesStore {
  final saveStarted = Completer<void>();
  final _releaseSave = Completer<void>();
  NeuraAdaptiveIntentPreferences? value;

  void release() {
    if (!_releaseSave.isCompleted) _releaseSave.complete();
  }

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<NeuraAdaptiveIntentPreferences?> load() async => value;

  @override
  Future<void> save(NeuraAdaptiveIntentPreferences preferences) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await _releaseSave.future;
    value = preferences;
  }
}
