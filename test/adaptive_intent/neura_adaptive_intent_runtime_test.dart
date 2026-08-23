import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_controller.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_runtime.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_plan_session.dart';

void main() {
  test('runtime owns one session and derives an outcome adaptation', () async {
    final controller = NeuraAdaptiveIntentController();
    final runtime = NeuraAdaptiveIntentRuntime(
      controller: controller,
      clock: () => DateTime.utc(2026, 8, 23, 10),
    );
    addTearDown(runtime.dispose);
    addTearDown(controller.dispose);

    final session = await runtime.startSession(
      'Organize my private launch list',
      now: DateTime.utc(2026, 8, 23, 9),
    );
    expect(session.status, NeuraPlanSessionStatus.active);
    await expectLater(
      runtime.startSession('Start another plan'),
      throwsStateError,
    );

    runtime.completeStep('organize-gather', userGesture: true);
    runtime.completeStep(
      'organize-groups',
      userGesture: true,
      approvalGranted: true,
    );
    runtime.deferStep('organize-next', userGesture: true);

    final outcome = runtime.finishSession(
      userGesture: true,
      perceivedEffort: 0.45,
      satisfaction: 0.80,
      interruptionCount: 1,
    );

    expect(outcome.completedLocalSteps, 2);
    expect(runtime.session, isNull);
    expect(runtime.lastOutcome, same(outcome));
    expect(runtime.lastAdaptation, isNotNull);
    expect(
      runtime.outcomes.single.toJson().toString(),
      isNot(contains('private launch list')),
    );
  });

  test('runtime fails closed when Safe Mode is active', () async {
    final controller = NeuraAdaptiveIntentController(safeMode: true);
    final runtime = NeuraAdaptiveIntentRuntime(controller: controller);
    addTearDown(runtime.dispose);
    addTearDown(controller.dispose);

    await expectLater(runtime.startSession('Plan my week'), throwsStateError);
    expect(runtime.session, isNull);
  });
}
