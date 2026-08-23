import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_plan_session.dart';
import 'package:neuro_companion/cognitive/neura_bandwidth_engine.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';
import 'package:neuro_companion/cognitive/neura_interface_policy.dart';
import 'package:neuro_companion/constitution/neura_personal_constitution.dart';
import 'package:neuro_companion/intent_compiler/neura_action_graph.dart';
import 'package:neuro_companion/intent_compiler/neura_intent_compiler.dart';

void main() {
  test('session requires direct gestures, approval, and a local executor', () {
    final session = NeuraAdaptivePlanSession.start(
      _weeklyGraph(),
      startedAt: DateTime.utc(2026, 8, 23, 9),
    );

    expect(
      () => session.completeStep('week-review', userGesture: false),
      throwsStateError,
    );
    session.completeStep('week-review', userGesture: true);
    expect(
      session.progressFor('week-review').status,
      NeuraPlanStepStatus.completed,
    );

    expect(
      () => session.completeStep('week-three', userGesture: true),
      throwsStateError,
    );
    session.completeStep(
      'week-three',
      userGesture: true,
      approvalGranted: true,
    );

    expect(
      () => session.completeStep(
        'week-blocks',
        userGesture: true,
        approvalGranted: true,
      ),
      throwsStateError,
    );
  });

  test('session closes with a derived receipt that excludes goal text', () {
    final session = NeuraAdaptivePlanSession.start(
      _weeklyGraph(),
      startedAt: DateTime.utc(2026, 8, 23, 9),
    );

    session.completeStep('week-review', userGesture: true);
    session.completeStep(
      'week-three',
      userGesture: true,
      approvalGranted: true,
    );
    session.deferStep('week-review-point', userGesture: true);

    final receipt = session.finish(
      userGesture: true,
      perceivedEffort: 0.55,
      satisfaction: 0.80,
      interruptionCount: 1,
      endedAt: DateTime.utc(2026, 8, 23, 10),
    );

    expect(receipt.status, NeuraPlanSessionStatus.completed);
    expect(receipt.completedLocalSteps, 2);
    expect(receipt.deferredLocalSteps, 1);
    expect(receipt.externalSteps, 1);
    expect(receipt.completionRatio, closeTo(2 / 3, 0.0001));

    final encoded = receipt.toJson().toString();
    expect(encoded, isNot(contains('Plan my private launch week')));
    expect(encoded, isNot(contains('Choose three outcomes')));
    expect(
      () => session.deferStep('week-review-point', userGesture: true),
      throwsStateError,
    );
  });
}

NeuraActionGraph _weeklyGraph() {
  const engine = NeuraBandwidthEngine();
  final state = engine.estimate(
    NeuraCognitiveSignals.defaults(),
    calculatedAt: DateTime.utc(2026, 8, 23, 9),
  );
  final policy = NeuraInterfacePolicy.forState(state);
  return const NeuraIntentCompiler().compile(
    outcome: 'Plan my private launch week',
    cognitiveState: state,
    interfacePolicy: policy,
    constitution: const NeuraPersonalConstitution(),
    now: DateTime.utc(2026, 8, 23, 9),
  );
}
