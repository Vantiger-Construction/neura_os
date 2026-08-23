import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_controller.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_preferences.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_runtime.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_plan_session.dart';
import 'package:neuro_companion/adaptive_intent/neura_outcome_store.dart';

void main() {
  test('derived outcomes survive a runtime restart without raw goal text', () async {
    final store = _MemoryOutcomeStore();

    final firstController = NeuraAdaptiveIntentController();
    final firstRuntime = NeuraAdaptiveIntentRuntime(
      controller: firstController,
      outcomeStore: store,
      clock: () => DateTime.utc(2026, 8, 23, 10),
    );
    addTearDown(firstRuntime.dispose);
    addTearDown(firstController.dispose);

    await firstRuntime.startSession(
      'Organize my private acquisition plan',
      now: DateTime.utc(2026, 8, 23, 9),
    );
    firstRuntime.completeStep('organize-gather', userGesture: true);
    firstRuntime.completeStep(
      'organize-groups',
      userGesture: true,
      approvalGranted: true,
    );
    firstRuntime.deferStep('organize-next', userGesture: true);
    await firstRuntime.finishSessionAndPersist(
      userGesture: true,
      perceivedEffort: 0.45,
      satisfaction: 0.80,
      interruptionCount: 1,
    );

    expect(store.values, hasLength(1));
    expect(
      store.values.single.toJson().toString(),
      isNot(contains('private acquisition plan')),
    );

    final secondController = NeuraAdaptiveIntentController();
    final secondRuntime = NeuraAdaptiveIntentRuntime(
      controller: secondController,
      outcomeStore: store,
    );
    addTearDown(secondRuntime.dispose);
    addTearDown(secondController.dispose);

    await secondRuntime.initialize();

    expect(secondRuntime.outcomes, hasLength(1));
    expect(
      secondRuntime.lastOutcome!.status,
      NeuraPlanSessionStatus.completed,
    );
    expect(secondRuntime.lastAdaptation, isNotNull);
  });

  test('persisted enrollment gates the production runtime', () async {
    final preferenceStore = _MemoryPreferencesStore();
    final preferences = NeuraAdaptiveIntentPreferencesController(
      store: preferenceStore,
    );
    final controller = NeuraAdaptiveIntentController();
    final runtime = NeuraAdaptiveIntentRuntime(
      controller: controller,
      preferencesController: preferences,
    );
    addTearDown(runtime.dispose);
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);

    await expectLater(
      runtime.startSession('Plan one local step'),
      throwsStateError,
    );

    await preferences.completeOnboarding(
      useMoodSignal: true,
      useFocusSignal: true,
      useQuestSignal: true,
      useActivitySignal: true,
    );
    final session = await runtime.startSession('Plan one local step');

    expect(session.status, NeuraPlanSessionStatus.active);
  });
}

class _MemoryOutcomeStore implements NeuraOutcomeStore {
  List<NeuraPlanOutcomeReceipt> values =
      <NeuraPlanOutcomeReceipt>[];

  @override
  Future<void> clear() async {
    values = <NeuraPlanOutcomeReceipt>[];
  }

  @override
  Future<List<NeuraPlanOutcomeReceipt>> load() async {
    return List<NeuraPlanOutcomeReceipt>.from(values);
  }

  @override
  Future<void> save(
    Iterable<NeuraPlanOutcomeReceipt> outcomes,
  ) async {
    values = List<NeuraPlanOutcomeReceipt>.from(outcomes);
  }
}

class _MemoryPreferencesStore
    implements NeuraAdaptiveIntentPreferencesStore {
  NeuraAdaptiveIntentPreferences? value;

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<NeuraAdaptiveIntentPreferences?> load() async => value;

  @override
  Future<void> save(
    NeuraAdaptiveIntentPreferences preferences,
  ) async {
    value = preferences;
  }
}
