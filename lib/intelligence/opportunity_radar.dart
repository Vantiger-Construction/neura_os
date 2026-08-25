import 'dart:convert';

import 'capability_registry.dart';
import 'models.dart';

/// Finds timely, explainable opportunities in an on-device intelligence
/// snapshot.
///
/// The radar is deliberately a pure proposal generator: it reads no stores,
/// schedules nothing, and never executes a capability. Its candidates still
/// have to pass through the autonomy kernel before the UI may surface them.
class NeuraOpportunityRadar {
  const NeuraOpportunityRadar({
    this.minimumSignalConfidence = 0.55,
    this.minimumEvidenceConfidence = 0.35,
    this.maximumSnapshotAge = const Duration(hours: 6),
    this.maximumCandidates = 4,
  })  : assert(minimumSignalConfidence >= 0),
        assert(minimumSignalConfidence <= 1),
        assert(minimumEvidenceConfidence >= 0),
        assert(minimumEvidenceConfidence <= 1),
        assert(maximumCandidates > 0);

  static const _futureTolerance = Duration(minutes: 5);
  static const _moodEvidenceAge = Duration(days: 3);
  static const _focusEvidenceAge = Duration(hours: 2);
  static const _questEvidenceAge = Duration(days: 14);
  static const _goalEvidenceAge = Duration(days: 180);

  final double minimumSignalConfidence;
  final double minimumEvidenceConfidence;
  final Duration maximumSnapshotAge;
  final int maximumCandidates;

  /// Returns highest-value candidates first.
  ///
  /// [now] is required rather than read from the system clock, keeping the
  /// result deterministic and making stale-signal behavior straightforward to
  /// test. Candidate ids depend only on their rule, evidence ids, and subject;
  /// rescanning the same snapshot therefore produces stable dedupe keys.
  List<NeuraIntelligenceCandidate> scan({
    required NeuraIntelligenceSnapshot snapshot,
    required DateTime now,
  }) {
    if (!_snapshotIsCurrent(snapshot, now)) {
      return const <NeuraIntelligenceCandidate>[];
    }

    final mood = _usableSignal(
      snapshot.signal(NeuraSignalKind.mood),
      now: now,
      maximumEvidenceAge: _moodEvidenceAge,
    );
    final focus = _usableSignal(
      snapshot.signal(NeuraSignalKind.focus),
      now: now,
      maximumEvidenceAge: _focusEvidenceAge,
    );
    final activeQuest = _usableSignal(
      snapshot.signal(NeuraSignalKind.activeQuest),
      now: now,
      maximumEvidenceAge: _questEvidenceAge,
    );
    final questMomentum = _usableSignal(
      snapshot.signal(NeuraSignalKind.questMomentum),
      now: now,
      maximumEvidenceAge: _questEvidenceAge,
    );
    final goal = _usableSignal(
      snapshot.signal(NeuraSignalKind.goal),
      now: now,
      maximumEvidenceAge: _goalEvidenceAge,
    );

    final candidates = <NeuraIntelligenceCandidate>[];
    final protectedFocus = focus != null && _isProtectedFocus(focus.signal);

    if (mood != null) {
      final severity = _lowMoodSeverity(mood.signal.numericValue);
      if (severity >= 0.55) {
        candidates.add(
          _candidate(
            rule: 'mood_reset',
            capabilityId: NeuraCapabilityRegistry.openAppModule,
            title: 'A gentle reset is available',
            body:
                'Your recent mood check-in is on the lower side. A short reset '
                'is available if you want it.',
            createdAt: now,
            lifetime: const Duration(hours: 4),
            evidence: mood.evidence,
            benefit: 0.88,
            urgency: 0.55 + severity * 0.40,
            disruption: 0.12,
            confidence: mood.signal.confidence,
            payload: const {
              'opportunity_kind': 'mood_reset',
              'module': 'mood_den',
            },
          ),
        );
      }
    }

    // Task nudges stay silent during a protected focus/wind-down state. Mood
    // support remains eligible and the autonomy kernel still owns the final
    // attention-policy decision.
    if (!protectedFocus) {
      if (activeQuest != null &&
          questMomentum != null &&
          _hasActiveQuest(activeQuest.signal)) {
        final momentum = _normaliseUnitValue(questMomentum.signal.numericValue);
        if (momentum != null && momentum <= 0.38) {
          final questName = _label(activeQuest.signal, 'your current quest');
          final evidence = _mergeEvidence(
            activeQuest.evidence,
            questMomentum.evidence,
          );
          candidates.add(
            _candidate(
              rule: 'quest_micro_step',
              subject: questName,
              capabilityId: NeuraCapabilityRegistry.openAppModule,
              title: 'Make the quest smaller',
              body: 'Momentum is quiet for "$questName". Choose one step that '
                  'takes less than five minutes.',
              createdAt: now,
              lifetime: const Duration(hours: 24),
              evidence: evidence,
              benefit: 0.78,
              urgency: 0.62,
              disruption: 0.16,
              confidence: _averageConfidence(
                activeQuest.signal,
                questMomentum.signal,
              ),
              payload: {
                'opportunity_kind': 'quest_micro_step',
                'module': 'quest_mode',
                'quest': questName,
              },
            ),
          );
        }
      }

      if (focus != null && _isLowFocus(focus.signal)) {
        candidates.add(
          _candidate(
            rule: 'focus_sprint',
            capabilityId: NeuraCapabilityRegistry.openAppModule,
            title: 'Try a 15-minute focus sprint',
            body: 'Your attention signal looks scattered. A short, optional '
                'focus sprint can make the next step easier to start.',
            createdAt: now,
            lifetime: const Duration(hours: 2),
            evidence: focus.evidence,
            benefit: 0.72,
            urgency: 0.48,
            disruption: 0.12,
            confidence: focus.signal.confidence,
            payload: const {
              'opportunity_kind': 'focus_sprint',
              'module': 'focus_office',
              'duration_minutes': 15,
            },
          ),
        );
      }

      if (goal != null && !_hasActiveQuest(activeQuest?.signal)) {
        final goalName = _label(goal.signal, 'your goal');
        candidates.add(
          _candidate(
            rule: 'goal_to_quest',
            subject: goalName,
            capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
            title: 'Turn a goal into one next step',
            body:
                'There is no active quest connected to "$goalName". Neura can '
                'draft one small step for your approval.',
            createdAt: now,
            lifetime: const Duration(days: 3),
            evidence: goal.evidence,
            benefit: 0.74,
            urgency: 0.42,
            disruption: 0.18,
            confidence: goal.signal.confidence,
            payload: {
              'opportunity_kind': 'goal_to_quest',
              'action': 'draft_quest',
              'goal': goalName,
            },
          ),
        );
      }
    }

    final unique = <String, NeuraIntelligenceCandidate>{};
    for (final candidate in candidates) {
      unique[candidate.id] = candidate;
    }
    final ranked = unique.values.toList()
      ..sort((a, b) {
        final scoreOrder = _rankScore(b).compareTo(_rankScore(a));
        return scoreOrder != 0 ? scoreOrder : a.id.compareTo(b.id);
      });

    return List.unmodifiable(ranked.take(maximumCandidates));
  }

  bool _snapshotIsCurrent(NeuraIntelligenceSnapshot snapshot, DateTime now) {
    if (maximumSnapshotAge <= Duration.zero) return false;
    if (snapshot.generatedAt.isAfter(now.add(_futureTolerance))) return false;
    return now.difference(snapshot.generatedAt) <= maximumSnapshotAge;
  }

  _UsableSignal? _usableSignal(
    NeuraFusedSignal? signal, {
    required DateTime now,
    required Duration maximumEvidenceAge,
  }) {
    if (signal == null || signal.confidence < minimumSignalConfidence) {
      return null;
    }

    final evidence = signal.evidence.where((item) {
      if (item.confidence < minimumEvidenceConfidence) return false;
      if (item.observedAt.isAfter(now.add(_futureTolerance))) return false;
      return now.difference(item.observedAt) <= maximumEvidenceAge;
    }).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (evidence.isEmpty) return null;
    return _UsableSignal(signal, List.unmodifiable(evidence));
  }

  NeuraIntelligenceCandidate _candidate({
    required String rule,
    String subject = '',
    required String capabilityId,
    required String title,
    required String body,
    required DateTime createdAt,
    required Duration lifetime,
    required List<NeuraEvidenceRef> evidence,
    required double benefit,
    required double urgency,
    required double disruption,
    required double confidence,
    required Map<String, Object?> payload,
  }) {
    return NeuraIntelligenceCandidate(
      id: _stableCandidateId(rule, subject, evidence),
      capabilityId: capabilityId,
      specialistId: 'opportunity_radar.$rule',
      title: title,
      body: body,
      createdAt: createdAt,
      expiresAt: createdAt.add(lifetime),
      evidence: List.unmodifiable(evidence),
      benefit: benefit,
      urgency: urgency,
      disruption: disruption,
      confidence: confidence,
      payload: Map.unmodifiable(payload),
    );
  }

  static List<NeuraEvidenceRef> _mergeEvidence(
    List<NeuraEvidenceRef> first,
    List<NeuraEvidenceRef> second,
  ) {
    final byId = <String, NeuraEvidenceRef>{};
    for (final item in [...first, ...second]) {
      byId[item.id] = item;
    }
    final merged = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(merged);
  }

  static bool _hasActiveQuest(NeuraFusedSignal? signal) {
    if (signal == null) return false;
    if (signal.label?.trim().isNotEmpty == true) return true;
    return (signal.numericValue ?? 0) > 0;
  }

  static bool _isLowFocus(NeuraFusedSignal signal) {
    final label = _normaliseLabel(signal.label);
    if (const {'distracted', 'scattered', 'low', 'off'}.contains(label)) {
      return true;
    }
    final focus = _normaliseUnitValue(signal.numericValue);
    return focus != null && focus <= 0.38;
  }

  static bool _isProtectedFocus(NeuraFusedSignal signal) {
    final label = _normaliseLabel(signal.label);
    if (const {
      'deepwork',
      'deep work',
      'deep_work',
      'winddown',
      'wind down',
      'wind_down',
    }.contains(label)) {
      return true;
    }
    final focus = _normaliseUnitValue(signal.numericValue);
    return focus != null && focus >= 0.72;
  }

  static double _lowMoodSeverity(double? value) {
    if (value == null || !value.isFinite) return 0;
    if (value < 0) {
      return (1 - ((value.clamp(-1.0, 1.0) + 1) / 2))
          .clamp(0.0, 1.0)
          .toDouble();
    }
    final normalised = _normaliseUnitValue(value);
    return normalised == null ? 0 : 1 - normalised;
  }

  /// Accepts the normalized 0..1 convention as well as existing Neura stores
  /// that use 0..10. Values over 10 are interpreted as percentages.
  static double? _normaliseUnitValue(double? value) {
    if (value == null || !value.isFinite || value < 0) return null;
    if (value <= 1) return value;
    if (value <= 10) return value / 10;
    if (value <= 100) return value / 100;
    return null;
  }

  static String _label(NeuraFusedSignal signal, String fallback) {
    final value = signal.label?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  static String _normaliseLabel(String? value) =>
      value?.trim().toLowerCase() ?? '';

  static double _averageConfidence(
    NeuraFusedSignal first,
    NeuraFusedSignal second,
  ) =>
      ((first.confidence + second.confidence) / 2).clamp(0.0, 1.0).toDouble();

  static double _rankScore(NeuraIntelligenceCandidate candidate) =>
      (candidate.benefit * 0.38 +
              candidate.urgency * 0.26 +
              candidate.confidence * 0.24 -
              candidate.disruption * 0.22)
          .clamp(0.0, 1.0)
          .toDouble();

  static String _stableCandidateId(
    String rule,
    String subject,
    Iterable<NeuraEvidenceRef> evidence,
  ) {
    final evidenceIds = evidence.map((item) => item.id).toSet().toList()
      ..sort();
    final canonical = [
      rule,
      subject.trim().toLowerCase(),
      ...evidenceIds,
    ].join('|');
    return 'radar:$rule:${_stableHash(canonical)}';
  }

  /// Two independent 31-bit rolling hashes. All intermediate values remain
  /// below JavaScript's exact-integer limit, so identifiers are stable across
  /// native and web builds.
  static String _stableHash(String value) {
    var first = 5381;
    var second = 17;
    for (final byte in utf8.encode(value)) {
      first = ((first * 33) ^ byte) & 0x7fffffff;
      second = ((second * 65599) + byte) & 0x7fffffff;
    }
    return '${first.toRadixString(16).padLeft(8, '0')}'
        '${second.toRadixString(16).padLeft(8, '0')}';
  }
}

class _UsableSignal {
  const _UsableSignal(this.signal, this.evidence);

  final NeuraFusedSignal signal;
  final List<NeuraEvidenceRef> evidence;
}
