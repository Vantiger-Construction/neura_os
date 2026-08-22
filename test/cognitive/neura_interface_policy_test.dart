import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';
import 'package:neuro_companion/cognitive/neura_interface_policy.dart';
import 'package:neuro_companion/intent_compiler/neura_action_graph.dart';

void main() {
  NeuraCognitiveState stateFor(NeuraBandwidthMode mode) {
    return NeuraCognitiveState(
      availableBandwidth: 0.5,
      cognitiveLoad: 0.5,
      energy: 0.5,
      urgency: 0.5,
      confidence: 0.9,
      mode: mode,
      calculatedAt: DateTime.utc(2026, 8, 22),
    );
  }

  test('recovery policy exposes one action and blocks external effects', () {
    final policy = NeuraInterfacePolicy.forState(
      stateFor(NeuraBandwidthMode.recovery),
    );

    expect(policy.maxPrimaryActions, 1);
    expect(policy.proactiveRecommendationsAllowed, isFalse);
    expect(policy.externalEffectsAllowed, isFalse);
    expect(policy.minimumApprovalTier, NeuraApprovalTier.elevated);
  });

  test('Safe Mode overrides a deep-focus state', () {
    final policy = NeuraInterfacePolicy.forState(
      stateFor(NeuraBandwidthMode.deepFocus),
      safeMode: true,
    );

    expect(policy.maxPrimaryActions, 1);
    expect(policy.automationDepth, NeuraAutomationDepth.suggestOnly);
    expect(policy.externalEffectsAllowed, isFalse);
  });

  test('balanced policy allows proposals but still requires confirmation', () {
    final policy = NeuraInterfacePolicy.forState(
      stateFor(NeuraBandwidthMode.balanced),
    );

    expect(policy.externalEffectsAllowed, isTrue);
    expect(policy.minimumApprovalTier, NeuraApprovalTier.confirm);
    expect(
      policy.automationDepth,
      NeuraAutomationDepth.localAfterConfirmation,
    );
  });
}
