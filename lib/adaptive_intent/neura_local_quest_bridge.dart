import '../cognitive/neura_cognitive_state.dart';
import '../intelligence/capability_registry.dart';
import '../intelligence/models.dart' as intelligence;
import '../intent_compiler/neura_action_graph.dart' as adaptive;

class NeuraLocalQuestProposal {
  const NeuraLocalQuestProposal({
    required this.candidate,
    required this.receipt,
  });

  final intelligence.NeuraIntelligenceCandidate candidate;
  final intelligence.NeuraDecisionReceipt receipt;
}

class NeuraLocalQuestBridge {
  NeuraLocalQuestBridge({NeuraCapabilityRegistry? registry})
      : _registry = registry ?? NeuraCapabilityRegistry();

  static final NeuraLocalQuestBridge instance = NeuraLocalQuestBridge();

  static const specialistId = 'adaptive_intent_local_quest';

  final NeuraCapabilityRegistry _registry;

  NeuraLocalQuestProposal prepare({
    required adaptive.NeuraActionStep step,
    required String sessionId,
    required NeuraCognitiveState cognitiveState,
    required bool safeMode,
    required bool userGesture,
    DateTime? now,
  }) {
    if (!userGesture) {
      throw StateError(
        'Preparing a local quest requires a direct user gesture.',
      );
    }
    if (safeMode) {
      throw StateError('Safe Mode blocks local quest preparation.');
    }
    if (cognitiveState.mode == NeuraBandwidthMode.recovery) {
      throw StateError(
        'Recovery mode remains suggestion-only and cannot prepare actions.',
      );
    }
    if (step.blocked) {
      throw StateError('A policy-blocked step cannot become a quest.');
    }
    if (_isExternal(step.effect)) {
      throw StateError('External effects cannot become local quests.');
    }
    if (step.effect != adaptive.NeuraActionEffect.localWrite) {
      throw StateError(
        'Only an explicit local-write step may become a quest.',
      );
    }

    final capability = _registry.resolve(
      NeuraCapabilityRegistry.changeLocalPlan,
    );
    if (capability.id != NeuraCapabilityRegistry.changeLocalPlan ||
        capability.risk != intelligence.NeuraCapabilityRisk.reversibleLocal ||
        capability.approvalMode != intelligence.NeuraApprovalMode.everyTime ||
        !capability.reversible ||
        capability.hasExternalSideEffect) {
      throw StateError(
        'The local-plan capability no longer satisfies Adaptive Intent safety.',
      );
    }

    final goal = _normalizeGoal(step.title);
    final evaluatedAt = (now ?? DateTime.now()).toUtc();
    final safeSession = _safeIdPart(sessionId);
    final safeStep = _safeIdPart(step.id);
    final candidateId = 'adaptive-quest:$safeSession:$safeStep:'
        '${evaluatedAt.microsecondsSinceEpoch}';

    final candidate = intelligence.NeuraIntelligenceCandidate(
      id: candidateId,
      capabilityId: capability.id,
      specialistId: specialistId,
      title: 'Create a reversible local quest',
      body: 'Review one on-device quest derived from the selected local plan '
          'step. Nothing is created until you approve it.',
      createdAt: evaluatedAt,
      expiresAt: evaluatedAt.add(const Duration(minutes: 10)),
      benefit: 0.65,
      urgency: cognitiveState.urgency,
      disruption: 0.12,
      confidence: cognitiveState.confidence,
      payload: <String, Object?>{
        'action': 'draft_quest',
        'goal': goal,
      },
    );
    final receipt = intelligence.NeuraDecisionReceipt(
      id: '$candidateId:receipt',
      candidateId: candidateId,
      capabilityId: capability.id,
      specialistId: specialistId,
      outcome: intelligence.NeuraDecisionOutcome.askApproval,
      risk: capability.risk,
      score: 0.65,
      requiresApproval: true,
      reasons: const <String>[
        'Adaptive Intent selected one allowed local-write step.',
        'The Capability Registry classifies this as reversible and local.',
        'Action Loom must revalidate the exact payload before execution.',
        'Fresh user approval is required every time.',
      ],
      evidenceIds: const <String>[],
      evaluatedAt: evaluatedAt,
    );
    return NeuraLocalQuestProposal(
      candidate: candidate,
      receipt: receipt,
    );
  }

  bool _isExternal(adaptive.NeuraActionEffect effect) {
    return switch (effect) {
      adaptive.NeuraActionEffect.localRead ||
      adaptive.NeuraActionEffect.localWrite =>
        false,
      _ => true,
    };
  }

  String _normalizeGoal(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      throw const FormatException('The local quest goal is empty.');
    }
    if (normalized.length > 160) {
      return normalized.substring(0, 160).trimRight();
    }
    return normalized;
  }

  String _safeIdPart(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-');
    if (normalized.isEmpty) return 'unknown';
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }
}
