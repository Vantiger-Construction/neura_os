import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_outcome_loop.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_plan_session.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';

void main() {
  const loop = NeuraAdaptiveOutcomeLoop();

  test('outcome loop reduces load after overloaded sessions', () {
    final adaptation = loop.evaluate(
      history: <NeuraPlanOutcomeReceipt>[
        _outcome(
          id: 'one',
          completion: 0.25,
          effort: 0.90,
          satisfaction: 0.30,
          interruptions: 6,
        ),
        _outcome(
          id: 'two',
          completion: 0.40,
          effort: 0.80,
          satisfaction: 0.40,
          interruptions: 4,
        ),
      ],
      currentState: _state(
        mode: NeuraBandwidthMode.balanced,
        bandwidth: 0.48,
        load: 0.70,
      ),
    );

    expect(adaptation.kind, NeuraOutcomeAdaptationKind.reduceLoad);
    expect(adaptation.recommendedMode, NeuraBandwidthMode.simplified);
    expect(adaptation.maxPrimaryActions, 2);
    expect(adaptation.suppressProactiveSuggestions, isTrue);
  });

  test('outcome loop protects focus only after repeated strong outcomes', () {
    final adaptation = loop.evaluate(
      history: <NeuraPlanOutcomeReceipt>[
        _outcome(
          id: 'one',
          completion: 0.90,
          effort: 0.50,
          satisfaction: 0.80,
          interruptions: 1,
        ),
        _outcome(
          id: 'two',
          completion: 1.0,
          effort: 0.55,
          satisfaction: 0.85,
          interruptions: 0,
        ),
      ],
      currentState: _state(
        mode: NeuraBandwidthMode.balanced,
        bandwidth: 0.75,
        load: 0.30,
      ),
    );

    expect(adaptation.kind, NeuraOutcomeAdaptationKind.protectFocus);
    expect(adaptation.recommendedMode, NeuraBandwidthMode.deepFocus);
    expect(adaptation.maxPrimaryActions, 3);
    expect(adaptation.suppressProactiveSuggestions, isTrue);
  });
}

NeuraPlanOutcomeReceipt _outcome({
  required String id,
  required double completion,
  required double effort,
  required double satisfaction,
  required int interruptions,
}) {
  return NeuraPlanOutcomeReceipt(
    sessionId: id,
    startedAt: DateTime.utc(2026, 8, 23, 9),
    endedAt: DateTime.utc(2026, 8, 23, 10),
    bandwidthMode: NeuraBandwidthMode.balanced,
    status: NeuraPlanSessionStatus.completed,
    totalLocalSteps: 4,
    completedLocalSteps: (completion * 4).round(),
    deferredLocalSteps: 0,
    blockedSteps: 0,
    externalSteps: 0,
    completionRatio: completion,
    perceivedEffort: effort,
    satisfaction: satisfaction,
    interruptionCount: interruptions,
  );
}

NeuraCognitiveState _state({
  required NeuraBandwidthMode mode,
  required double bandwidth,
  required double load,
}) {
  return NeuraCognitiveState(
    availableBandwidth: bandwidth,
    cognitiveLoad: load,
    energy: 0.70,
    urgency: 0.30,
    confidence: 0.85,
    mode: mode,
    calculatedAt: DateTime.utc(2026, 8, 23, 10),
  );
}
