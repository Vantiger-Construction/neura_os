import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_local_quest_bridge.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/models.dart' as intelligence;
import 'package:neuro_companion/intent_compiler/neura_action_graph.dart';

void main() {
  final bridge = NeuraLocalQuestBridge();

  test('bridge prepares exactly one fresh-approval local quest proposal', () {
    final proposal = bridge.prepare(
      step: _step(),
      sessionId: 'session-1',
      cognitiveState: _state(NeuraBandwidthMode.balanced),
      safeMode: false,
      userGesture: true,
      now: DateTime.utc(2026, 8, 23, 12),
    );

    expect(
      proposal.candidate.capabilityId,
      NeuraCapabilityRegistry.changeLocalPlan,
    );
    expect(proposal.candidate.payload['action'], 'draft_quest');
    expect(proposal.candidate.payload['goal'], 'Choose one next step');
    expect(
      proposal.receipt.outcome,
      intelligence.NeuraDecisionOutcome.askApproval,
    );
    expect(proposal.receipt.requiresApproval, isTrue);
    expect(
      proposal.receipt.risk,
      intelligence.NeuraCapabilityRisk.reversibleLocal,
    );
  });

  test('bridge fails closed without gesture, in Safe Mode, or for external work', () {
    expect(
      () => bridge.prepare(
        step: _step(),
        sessionId: 'session',
        cognitiveState: _state(NeuraBandwidthMode.balanced),
        safeMode: false,
        userGesture: false,
      ),
      throwsStateError,
    );
    expect(
      () => bridge.prepare(
        step: _step(),
        sessionId: 'session',
        cognitiveState: _state(NeuraBandwidthMode.balanced),
        safeMode: true,
        userGesture: true,
      ),
      throwsStateError,
    );
    expect(
      () => bridge.prepare(
        step: _step(effect: NeuraActionEffect.externalMessage),
        sessionId: 'session',
        cognitiveState: _state(NeuraBandwidthMode.balanced),
        safeMode: false,
        userGesture: true,
      ),
      throwsStateError,
    );
    expect(
      () => bridge.prepare(
        step: _step(),
        sessionId: 'session',
        cognitiveState: _state(NeuraBandwidthMode.recovery),
        safeMode: false,
        userGesture: true,
      ),
      throwsStateError,
    );
  });
}

NeuraActionStep _step({
  NeuraActionEffect effect = NeuraActionEffect.localWrite,
}) {
  return NeuraActionStep(
    id: 'next-step',
    title: 'Choose one next step',
    description: 'Select the smallest useful action.',
    effect: effect,
    requiredApproval: NeuraApprovalTier.confirm,
    reversible: true,
    estimatedMinutes: 5,
    priority: 100,
  );
}

NeuraCognitiveState _state(NeuraBandwidthMode mode) {
  return NeuraCognitiveState(
    availableBandwidth:
        mode == NeuraBandwidthMode.recovery ? 0.20 : 0.65,
    cognitiveLoad:
        mode == NeuraBandwidthMode.recovery ? 0.85 : 0.40,
    energy: 0.60,
    urgency: 0.45,
    confidence: 0.80,
    mode: mode,
    calculatedAt: DateTime.utc(2026, 8, 23, 12),
  );
}
