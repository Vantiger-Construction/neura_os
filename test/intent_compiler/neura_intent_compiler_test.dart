import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/cognitive/neura_bandwidth_engine.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';
import 'package:neuro_companion/cognitive/neura_interface_policy.dart';
import 'package:neuro_companion/constitution/neura_personal_constitution.dart';
import 'package:neuro_companion/intent_compiler/neura_action_graph.dart';
import 'package:neuro_companion/intent_compiler/neura_intent.dart';
import 'package:neuro_companion/intent_compiler/neura_intent_compiler.dart';

void main() {
  const engine = NeuraBandwidthEngine();
  const compiler = NeuraIntentCompiler();

  NeuraCognitiveState balancedState() {
    return engine.estimate(
      const NeuraCognitiveSignals(
        energy: 0.72,
        focus: 0.58,
        cognitiveLoad: 0.35,
        urgency: 0.42,
        taskSwitchRate: 0.30,
        completionRate: 0.62,
        notificationPressure: 0.30,
      ),
      calculatedAt: DateTime.utc(2026, 8, 22, 15),
    );
  }

  test('weekly outcome compiles into a reversible local-first plan', () {
    final state = balancedState();
    final graph = compiler.compile(
      outcome: 'Plan my work week',
      cognitiveState: state,
      interfacePolicy: NeuraInterfacePolicy.forState(state),
      constitution: const NeuraPersonalConstitution(),
      now: DateTime.utc(2026, 8, 22, 15),
    );

    expect(graph.intent.kind, NeuraIntentKind.weeklyPlan);
    expect(graph.steps.first.effect, NeuraActionEffect.localRead);
    expect(graph.steps.first.requiredApproval, NeuraApprovalTier.none);
    expect(graph.steps.any((step) => step.reversible), isTrue);
    expect(graph.receipt.reasons, isNotEmpty);
  });

  test('default constitution blocks purchase and cloud steps', () {
    final state = balancedState();
    final graph = compiler.compile(
      outcome: 'Buy a new laptop',
      cognitiveState: state,
      interfacePolicy: NeuraInterfacePolicy.forState(state),
      constitution: const NeuraPersonalConstitution(),
      now: DateTime.utc(2026, 8, 22, 15),
    );

    expect(graph.intent.kind, NeuraIntentKind.purchase);
    expect(
      graph.blockedSteps.map((step) => step.effect),
      containsAll(<NeuraActionEffect>[
        NeuraActionEffect.cloudRequest,
        NeuraActionEffect.purchase,
      ]),
    );
  });

  test('recovery state exposes only one primary action', () {
    final state = engine.estimate(
      const NeuraCognitiveSignals(
        energy: 0.15,
        focus: 0.20,
        cognitiveLoad: 0.90,
        urgency: 0.80,
        taskSwitchRate: 0.85,
        completionRate: 0.10,
        notificationPressure: 0.90,
      ),
      calculatedAt: DateTime.utc(2026, 8, 22, 15),
    );
    final graph = compiler.compile(
      outcome: 'I am overwhelmed and need a reset',
      cognitiveState: state,
      interfacePolicy: NeuraInterfacePolicy.forState(state),
      constitution: const NeuraPersonalConstitution(),
      now: DateTime.utc(2026, 8, 22, 15),
    );

    expect(state.mode, NeuraBandwidthMode.recovery);
    expect(graph.primarySteps, hasLength(1));
    expect(graph.deferredSteps, isNotEmpty);
    expect(graph.steps.every((step) => !step.effect.isExternal), isTrue);
  });

  test('Safe Mode blocks external message even when constitution allows it', () {
    final state = engine.estimate(
      NeuraCognitiveSignals.defaults(),
      safeMode: true,
      calculatedAt: DateTime.utc(2026, 8, 22, 15),
    );
    final graph = compiler.compile(
      outcome: 'Send a message to my client',
      cognitiveState: state,
      interfacePolicy: NeuraInterfacePolicy.forState(state, safeMode: true),
      constitution: const NeuraPersonalConstitution(
        allowExternalMessages: true,
      ),
      safeMode: true,
      now: DateTime.utc(2026, 8, 22, 15),
    );

    expect(
      graph.blockedSteps.any(
        (step) => step.effect == NeuraActionEffect.externalMessage,
      ),
      isTrue,
    );
  });
}
