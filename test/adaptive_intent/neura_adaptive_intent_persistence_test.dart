import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_controller.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_store.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';
import 'package:neuro_companion/constitution/neura_personal_constitution.dart';

void main() {
  test('shared controller restores fresh local state and follows Safe Mode',
      () async {
    final safeMode = ValueNotifier<bool>(false);
    final store = _MemoryStore(
      NeuraAdaptiveIntentSnapshot(
        signals: const NeuraCognitiveSignals(
          energy: 0.82,
          focus: 0.76,
          cognitiveLoad: 0.18,
          urgency: 0.22,
          taskSwitchRate: 0.12,
          completionRate: 0.84,
          notificationPressure: 0.10,
        ),
        constitution: const NeuraPersonalConstitution(
          allowCloudAi: true,
          allowCalendarWrites: false,
          workHoursStart: 8,
          workHoursEnd: 18,
        ),
        savedAt: DateTime.utc(2026, 8, 22, 12),
      ),
    );
    final controller = NeuraAdaptiveIntentController(
      store: store,
      safeModeListenable: safeMode,
      clock: () => DateTime.utc(2026, 8, 22, 15),
      persistDelay: Duration.zero,
    );
    addTearDown(() {
      controller.dispose();
      safeMode.dispose();
    });

    await controller.initialize();

    expect(controller.signals.energy, 0.82);
    expect(controller.constitution.allowCloudAi, isTrue);
    expect(controller.constitution.allowCalendarWrites, isFalse);
    expect(controller.constitution.workHoursStart, 8);
    expect(controller.safeMode, isFalse);

    safeMode.value = true;

    expect(controller.safeMode, isTrue);
    expect(controller.state.mode, NeuraBandwidthMode.recovery);
    expect(controller.interfacePolicy.externalEffectsAllowed, isFalse);
  });

  test('stale capacity signals expire while constitution choices remain',
      () async {
    final store = _MemoryStore(
      NeuraAdaptiveIntentSnapshot(
        signals: const NeuraCognitiveSignals(
          energy: 0.05,
          focus: 0.05,
          cognitiveLoad: 0.98,
          urgency: 0.90,
          taskSwitchRate: 0.95,
          completionRate: 0.04,
          notificationPressure: 0.94,
        ),
        constitution: const NeuraPersonalConstitution(
          allowExternalMessages: true,
        ),
        savedAt: DateTime.utc(2026, 8, 21, 1),
      ),
    );
    final controller = NeuraAdaptiveIntentController(
      store: store,
      clock: () => DateTime.utc(2026, 8, 22, 15),
      persistDelay: Duration.zero,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(
      controller.signals.energy,
      NeuraCognitiveSignals.defaults().energy,
    );
    expect(controller.constitution.allowExternalMessages, isTrue);
  });

  test('only signals and constitution are persisted, never compiled goals',
      () async {
    final store = _MemoryStore();
    final controller = NeuraAdaptiveIntentController(
      store: store,
      clock: () => DateTime.utc(2026, 8, 22, 15),
      persistDelay: Duration.zero,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    controller.compileOutcome(
      'Private goal that must remain process-local',
      now: DateTime.utc(2026, 8, 22, 15),
    );
    controller.updateSignals(energy: 0.71);
    controller.updateConstitution(
      controller.constitution.copyWith(allowCloudAi: true),
    );
    await controller.flush();

    expect(store.writes, greaterThan(0));
    expect(store.snapshot?.signals.energy, 0.71);
    expect(store.snapshot?.constitution.allowCloudAi, isTrue);
    expect(
      store.snapshot!.toJson().toString(),
      isNot(contains('Private goal')),
    );
  });

  test('failed initialization can be retried', () async {
    final store = _MemoryStore()..failLoads = 1;
    final controller = NeuraAdaptiveIntentController(
      store: store,
      persistDelay: Duration.zero,
    );
    addTearDown(controller.dispose);

    await expectLater(controller.initialize(), throwsStateError);
    expect(controller.initialized, isFalse);

    await controller.initialize();

    expect(controller.initialized, isTrue);
    expect(store.loads, 2);
  });
}

class _MemoryStore implements NeuraAdaptiveIntentStore {
  _MemoryStore([this.snapshot]);

  NeuraAdaptiveIntentSnapshot? snapshot;
  int writes = 0;
  int loads = 0;
  int failLoads = 0;

  @override
  Future<NeuraAdaptiveIntentSnapshot?> load() async {
    loads += 1;
    if (failLoads > 0) {
      failLoads -= 1;
      throw StateError('transient load failure');
    }
    return snapshot;
  }

  @override
  Future<void> save(NeuraAdaptiveIntentSnapshot snapshot) async {
    writes += 1;
    this.snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}
