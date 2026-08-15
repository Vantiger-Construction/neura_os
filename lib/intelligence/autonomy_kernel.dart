import 'capability_registry.dart';
import 'consent_ledger.dart';
import 'models.dart';

typedef NeuraReceiptIdFactory = String Function(
  NeuraIntelligenceCandidate candidate,
  DateTime now,
);

class NeuraAutonomyPolicy {
  const NeuraAutonomyPolicy({
    required this.enabled,
    required this.allowSensitiveSignals,
    required this.maxDailySuggestions,
    required this.suggestionsToday,
    required this.suggestionsLastHour,
    required this.focusMode,
    required this.safeMode,
    required this.recentlyDeclined,
    this.quietHours = false,
  });

  final bool enabled;
  final bool allowSensitiveSignals;
  final int maxDailySuggestions;
  final int suggestionsToday;
  final int suggestionsLastHour;
  final String focusMode;
  final bool safeMode;
  final bool recentlyDeclined;
  final bool quietHours;
}

/// Consent-first scoring and suppression boundary for proactive intelligence.
///
/// This kernel never executes a candidate. It produces an explainable receipt
/// that a separate approval broker or user-interface gesture must honor.
class NeuraAutonomyKernel {
  NeuraAutonomyKernel({
    NeuraCapabilityRegistry? registry,
    NeuraConsentLedger? consentLedger,
    NeuraReceiptIdFactory? receiptIdFactory,
  })  : registry = registry ?? NeuraCapabilityRegistry(),
        consentLedger = consentLedger ?? NeuraConsentLedger(),
        _receiptIdFactory = receiptIdFactory ?? _defaultReceiptId;

  final NeuraCapabilityRegistry registry;
  final NeuraConsentLedger consentLedger;
  final NeuraReceiptIdFactory _receiptIdFactory;

  NeuraDecisionReceipt evaluate({
    required NeuraIntelligenceCandidate candidate,
    required NeuraAutonomyPolicy policy,
    required DateTime now,
  }) {
    final capability = registry.resolve(candidate.capabilityId);
    final reasons = <String>[
      '${candidate.specialistId} supplied the candidate.',
      'Autonomy Guardian classified ${capability.title.toLowerCase()} as ${capability.risk.name}.',
    ];
    var outcome = NeuraDecisionOutcome.allow;
    var requiresApproval = false;

    final riskPenalty = switch (capability.risk) {
      NeuraCapabilityRisk.readOnly => 0.0,
      NeuraCapabilityRisk.reversibleLocal => 0.04,
      NeuraCapabilityRisk.sensitiveLocal => 0.14,
      NeuraCapabilityRisk.external => 0.24,
      NeuraCapabilityRisk.critical => 0.55,
    };
    final declinePenalty = policy.recentlyDeclined ? 0.15 : 0.0;
    final rawScore = candidate.benefit * 0.36 +
        candidate.confidence * 0.24 +
        candidate.urgency * 0.24 -
        candidate.disruption * 0.28 -
        riskPenalty -
        declinePenalty;
    final score = rawScore.clamp(0.0, 1.0).toDouble();

    if (!policy.enabled) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add('Proactive intelligence is disabled by the user.');
    } else if (policy.safeMode) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add('Attention Guardian suppresses proactive cards in Safe Mode.');
    } else if (policy.quietHours) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add('Attention Guardian is honoring quiet hours or a pause.');
    } else if (!now.isBefore(candidate.expiresAt)) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add('The opportunity expired before it could be shown.');
    } else if (capability.approvalMode == NeuraApprovalMode.blocked ||
        capability.risk == NeuraCapabilityRisk.critical) {
      outcome = NeuraDecisionOutcome.blocked;
      reasons.add('Safety Guardian blocks this capability from autonomous use.');
    } else if (!policy.allowSensitiveSignals &&
        candidate.evidence.any(
          (evidence) => evidence.sensitivity == NeuraSensitivity.sensitive,
        )) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add('Privacy Guardian excluded sensitive evidence by user policy.');
    } else if ((policy.focusMode == 'deepWork' ||
            policy.focusMode == 'windDown') &&
        candidate.urgency < 0.85) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add(
        'Attention Guardian protected the active ${policy.focusMode} mode.',
      );
    } else if (policy.suggestionsToday >= policy.maxDailySuggestions) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add('The user-controlled daily suggestion limit was reached.');
    } else if (policy.suggestionsLastHour >= 2) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add('Attention Guardian limits Neura to two suggestions per hour.');
    } else if (score < 0.38) {
      outcome = NeuraDecisionOutcome.suppressed;
      reasons.add('Expected benefit did not outweigh interruption and risk.');
    } else {
      final granted = consentLedger.isGranted(capability, now: now);
      if (!granted) {
        outcome = NeuraDecisionOutcome.askApproval;
        requiresApproval = true;
        reasons.add('This capability requires a fresh user confirmation.');
      } else {
        reasons.add('The candidate passed privacy, attention, and consent checks.');
      }
    }

    if (policy.recentlyDeclined) {
      reasons.add('A recent dismissal reduced the candidate score.');
    }

    return NeuraDecisionReceipt(
      id: _receiptIdFactory(candidate, now),
      candidateId: candidate.id,
      capabilityId: candidate.capabilityId,
      specialistId: candidate.specialistId,
      outcome: outcome,
      risk: capability.risk,
      score: score,
      requiresApproval: requiresApproval,
      reasons: List.unmodifiable(reasons),
      evidenceIds: List.unmodifiable(
        candidate.evidence
            .where(
              (evidence) => policy.allowSensitiveSignals ||
                  evidence.sensitivity != NeuraSensitivity.sensitive,
            )
            .map((evidence) => evidence.id),
      ),
      evaluatedAt: now,
    );
  }

  static String _defaultReceiptId(
    NeuraIntelligenceCandidate candidate,
    DateTime now,
  ) =>
      '${candidate.id}:${now.microsecondsSinceEpoch}';
}
