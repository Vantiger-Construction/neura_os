import 'package:flutter/foundation.dart';

enum NeuraSignalKind {
  mood,
  energy,
  focus,
  activeQuest,
  questMomentum,
  goal,
  relationshipRecency,
  stormRisk,
  preference,
}

enum NeuraSensitivity { routine, personal, sensitive }

enum NeuraCapabilityRisk {
  readOnly,
  reversibleLocal,
  sensitiveLocal,
  external,
  critical,
}

enum NeuraApprovalMode { none, session, everyTime, blocked }

enum NeuraDecisionOutcome { allow, askApproval, suppressed, blocked }

enum NeuraSuggestionOutcome { evaluated, shown, acted, dismissed, expired }

@immutable
class NeuraSignalObservation {
  NeuraSignalObservation({
    required this.id,
    required this.kind,
    required this.source,
    required this.summary,
    required this.observedAt,
    this.numericValue,
    this.label,
    this.confidence = 1,
    this.sensitivity = NeuraSensitivity.routine,
    this.validFor = const Duration(days: 1),
  }) : confidence = confidence.clamp(0.0, 1.0).toDouble();

  final String id;
  final NeuraSignalKind kind;
  final String source;
  final String summary;
  final DateTime observedAt;
  final double? numericValue;
  final String? label;
  final double confidence;
  final NeuraSensitivity sensitivity;
  final Duration validFor;

  bool isExpiredAt(DateTime now) =>
      !now.isBefore(observedAt.add(validFor));
}

@immutable
class NeuraEvidenceRef {
  const NeuraEvidenceRef({
    required this.id,
    required this.source,
    required this.summary,
    required this.observedAt,
    required this.confidence,
    required this.sensitivity,
  });

  final String id;
  final String source;
  final String summary;
  final DateTime observedAt;
  final double confidence;
  final NeuraSensitivity sensitivity;

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        'summary': summary,
        'observed_at': observedAt.toUtc().toIso8601String(),
        'confidence': confidence,
        'sensitivity': sensitivity.name,
      };

  factory NeuraEvidenceRef.fromJson(Map<String, Object?> json) {
    return NeuraEvidenceRef(
      id: json['id']?.toString() ?? '',
      source: json['source']?.toString() ?? 'unknown',
      summary: json['summary']?.toString() ?? 'On-device signal',
      observedAt: DateTime.tryParse(
            json['observed_at']?.toString() ?? '',
          )?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      confidence:
          _double(json['confidence'], 0).clamp(0.0, 1.0).toDouble(),
      sensitivity: _enumByName(
        NeuraSensitivity.values,
        json['sensitivity'],
        NeuraSensitivity.personal,
      ),
    );
  }
}

@immutable
class NeuraFusedSignal {
  const NeuraFusedSignal({
    required this.kind,
    required this.confidence,
    required this.evidence,
    this.numericValue,
    this.label,
  });

  final NeuraSignalKind kind;
  final double? numericValue;
  final String? label;
  final double confidence;
  final List<NeuraEvidenceRef> evidence;
}

@immutable
class NeuraIntelligenceSnapshot {
  NeuraIntelligenceSnapshot({
    required this.generatedAt,
    required Iterable<NeuraFusedSignal> signals,
  }) : signals = Map.unmodifiable({
          for (final signal in signals) signal.kind: signal,
        });

  final DateTime generatedAt;
  final Map<NeuraSignalKind, NeuraFusedSignal> signals;

  NeuraFusedSignal? signal(NeuraSignalKind kind) => signals[kind];

  double? value(NeuraSignalKind kind) => signals[kind]?.numericValue;

  String? label(NeuraSignalKind kind) => signals[kind]?.label;
}

@immutable
class NeuraCapabilityDefinition {
  const NeuraCapabilityDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.risk,
    required this.approvalMode,
    required this.reversible,
    required this.hasExternalSideEffect,
  });

  final String id;
  final String title;
  final String description;
  final NeuraCapabilityRisk risk;
  final NeuraApprovalMode approvalMode;
  final bool reversible;
  final bool hasExternalSideEffect;
}

@immutable
class NeuraIntelligenceCandidate {
  NeuraIntelligenceCandidate({
    required this.id,
    required this.capabilityId,
    required this.specialistId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    Iterable<NeuraEvidenceRef> evidence = const [],
    this.benefit = 0.5,
    this.urgency = 0.5,
    this.disruption = 0.5,
    this.confidence = 0.5,
    Map<String, Object?> payload = const {},
  })  : evidence = List<NeuraEvidenceRef>.unmodifiable(evidence),
        payload = Map<String, Object?>.unmodifiable(
          payload.map(
            (key, value) => MapEntry(key, _freezeJsonValue(value)),
          ),
        ),
        benefit = benefit.clamp(0.0, 1.0).toDouble(),
        urgency = urgency.clamp(0.0, 1.0).toDouble(),
        disruption = disruption.clamp(0.0, 1.0).toDouble(),
        confidence = confidence.clamp(0.0, 1.0).toDouble();

  final String id;
  final String capabilityId;
  final String specialistId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<NeuraEvidenceRef> evidence;
  final double benefit;
  final double urgency;
  final double disruption;
  final double confidence;
  final Map<String, Object?> payload;
}

@immutable
class NeuraDecisionReceipt {
  NeuraDecisionReceipt({
    required this.id,
    required this.candidateId,
    required this.capabilityId,
    required this.specialistId,
    required this.outcome,
    required this.risk,
    required this.score,
    required this.requiresApproval,
    required Iterable<String> reasons,
    required Iterable<String> evidenceIds,
    required this.evaluatedAt,
    this.userOutcome = NeuraSuggestionOutcome.evaluated,
  })  : reasons = List<String>.unmodifiable(reasons),
        evidenceIds = List<String>.unmodifiable(evidenceIds);

  final String id;
  final String candidateId;
  final String capabilityId;
  final String specialistId;
  final NeuraDecisionOutcome outcome;
  final NeuraCapabilityRisk risk;
  final double score;
  final bool requiresApproval;
  final List<String> reasons;
  final List<String> evidenceIds;
  final DateTime evaluatedAt;
  final NeuraSuggestionOutcome userOutcome;

  bool get isVisible =>
      outcome == NeuraDecisionOutcome.allow ||
      outcome == NeuraDecisionOutcome.askApproval;

  NeuraDecisionReceipt copyWith({
    NeuraDecisionOutcome? outcome,
    double? score,
    bool? requiresApproval,
    List<String>? reasons,
    NeuraSuggestionOutcome? userOutcome,
  }) {
    return NeuraDecisionReceipt(
      id: id,
      candidateId: candidateId,
      capabilityId: capabilityId,
      specialistId: specialistId,
      outcome: outcome ?? this.outcome,
      risk: risk,
      score: score ?? this.score,
      requiresApproval: requiresApproval ?? this.requiresApproval,
      reasons: reasons ?? this.reasons,
      evidenceIds: evidenceIds,
      evaluatedAt: evaluatedAt,
      userOutcome: userOutcome ?? this.userOutcome,
    );
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'candidate_id': candidateId,
        'capability_id': capabilityId,
        'specialist_id': specialistId,
        'outcome': outcome.name,
        'risk': risk.name,
        'score': score,
        'requires_approval': requiresApproval,
        'reasons': reasons,
        'evidence_ids': evidenceIds,
        'evaluated_at': evaluatedAt.toUtc().toIso8601String(),
        'user_outcome': userOutcome.name,
      };

  factory NeuraDecisionReceipt.fromJson(Map<String, Object?> json) {
    return NeuraDecisionReceipt(
      id: json['id']?.toString() ?? '',
      candidateId: json['candidate_id']?.toString() ?? '',
      capabilityId: json['capability_id']?.toString() ?? '',
      specialistId: json['specialist_id']?.toString() ?? 'unknown',
      outcome: _enumByName(
        NeuraDecisionOutcome.values,
        json['outcome'],
        NeuraDecisionOutcome.blocked,
      ),
      risk: _enumByName(
        NeuraCapabilityRisk.values,
        json['risk'],
        NeuraCapabilityRisk.critical,
      ),
      score: _double(json['score'], 0).clamp(0.0, 1.0).toDouble(),
      requiresApproval: json['requires_approval'] == true,
      reasons: _stringList(json['reasons']),
      evidenceIds: _stringList(json['evidence_ids']),
      evaluatedAt: DateTime.tryParse(
            json['evaluated_at']?.toString() ?? '',
          )?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      userOutcome: _enumByName(
        NeuraSuggestionOutcome.values,
        json['user_outcome'],
        NeuraSuggestionOutcome.evaluated,
      ),
    );
  }
}

Object? _freezeJsonValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, nested) => MapEntry(key.toString(), _freezeJsonValue(nested)),
      ),
    );
  }
  if (value is Iterable) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  return value;
}

@immutable
class NeuraCouncilDecision {
  const NeuraCouncilDecision({
    required this.candidate,
    required this.receipt,
  });

  final NeuraIntelligenceCandidate candidate;
  final NeuraDecisionReceipt receipt;
}

@immutable
class NeuraCouncilResult {
  const NeuraCouncilResult(this.decisions);

  final List<NeuraCouncilDecision> decisions;

  List<NeuraCouncilDecision> get visible {
    final result = decisions.where((item) => item.receipt.isVisible).toList()
      ..sort((a, b) => b.receipt.score.compareTo(a.receipt.score));
    return List.unmodifiable(result);
  }
}

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

List<String> _stringList(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
