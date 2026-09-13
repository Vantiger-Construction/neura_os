import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/intelligence/opportunity_radar.dart';

void main() {
  final now = DateTime.utc(2026, 8, 14, 18);
  const radar = NeuraOpportunityRadar();

  group('NeuraOpportunityRadar', () {
    test('suppresses stale snapshots, stale evidence, and low confidence', () {
      final otherwiseUsefulMood = _signal(
        NeuraSignalKind.mood,
        value: 0.1,
        confidence: 0.9,
        evidence: [_evidence('mood-1', now.subtract(const Duration(hours: 1)))],
      );

      expect(
        radar.scan(
          snapshot: _snapshot(
            now.subtract(const Duration(hours: 7)),
            [otherwiseUsefulMood],
          ),
          now: now,
        ),
        isEmpty,
      );

      expect(
        radar.scan(
          snapshot: _snapshot(now, [
            _signal(
              NeuraSignalKind.mood,
              value: 0.1,
              confidence: 0.4,
              evidence: [
                _evidence('mood-2', now.subtract(const Duration(hours: 1))),
              ],
            ),
          ]),
          now: now,
        ),
        isEmpty,
      );

      expect(
        radar.scan(
          snapshot: _snapshot(now, [
            _signal(
              NeuraSignalKind.mood,
              value: 0.1,
              confidence: 0.9,
              evidence: [
                _evidence('mood-3', now.subtract(const Duration(days: 4))),
              ],
            ),
          ]),
          now: now,
        ),
        isEmpty,
      );
    });

    test('creates and ranks mood, quest, and focus opportunities', () {
      final result = radar.scan(
        snapshot: _snapshot(now, [
          _signal(
            NeuraSignalKind.mood,
            value: 0.15,
            evidence: [_evidence('mood-low', now)],
          ),
          _signal(
            NeuraSignalKind.activeQuest,
            label: 'Ship Neura 1.3',
            evidence: [_evidence('quest-active', now)],
          ),
          _signal(
            NeuraSignalKind.questMomentum,
            value: 0.1,
            evidence: [_evidence('quest-slow', now)],
          ),
          _signal(
            NeuraSignalKind.focus,
            value: 0.2,
            label: 'scattered',
            evidence: [_evidence('focus-low', now)],
          ),
          _signal(
            NeuraSignalKind.goal,
            label: 'Launch Neura',
            evidence: [_evidence('goal-1', now)],
          ),
        ]),
        now: now,
      );

      expect(
        result.map((item) => item.payload['opportunity_kind']),
        ['mood_reset', 'quest_micro_step', 'focus_sprint'],
      );
      expect(
        result.every(
          (item) => item.capabilityId == NeuraCapabilityRegistry.openAppModule,
        ),
        isTrue,
      );
      expect(result.expand((item) => item.evidence), isNotEmpty);
    });

    test('offers an approval-gated quest draft for a goal with no active quest',
        () {
      final result = radar.scan(
        snapshot: _snapshot(now, [
          _signal(
            NeuraSignalKind.goal,
            label: 'Finish the recovery guide',
            evidence: [_evidence('goal-recovery', now)],
          ),
        ]),
        now: now,
      );

      expect(result, hasLength(1));
      expect(result.single.payload['opportunity_kind'], 'goal_to_quest');
      expect(
        result.single.capabilityId,
        NeuraCapabilityRegistry.changeLocalPlan,
      );
      expect(result.single.payload['action'], 'draft_quest');
    });

    test('offers care support only for a very severe, sustained low mood', () {
      final moderatelyLow = radar.scan(
        snapshot: _snapshot(now, [
          _signal(
            NeuraSignalKind.mood,
            value: 0.15, // severity 0.85 -- below the care-support bar.
            evidence: [_evidence('mood-moderate', now)],
          ),
        ]),
        now: now,
      );
      expect(
        moderatelyLow.map((item) => item.payload['opportunity_kind']),
        isNot(contains('care_support')),
      );

      final severelyLow = radar.scan(
        snapshot: _snapshot(now, [
          _signal(
            NeuraSignalKind.mood,
            value: 0.05, // severity 0.95.
            evidence: [_evidence('mood-severe', now)],
          ),
        ]),
        now: now,
      );
      expect(
        severelyLow.map((item) => item.payload['opportunity_kind']),
        ['care_support', 'mood_reset'],
      );
      expect(
        severelyLow.every(
          (item) => item.capabilityId == NeuraCapabilityRegistry.openAppModule,
        ),
        isTrue,
      );
    });

    test('flags a dream/mood correlation only when both signals point low', () {
      final lowMoodOnly = radar.scan(
        snapshot: _snapshot(now, [
          _signal(
            NeuraSignalKind.mood,
            value: 0.15, // severity 0.85.
            evidence: [_evidence('mood-1', now)],
          ),
        ]),
        now: now,
      );
      expect(
        lowMoodOnly.map((item) => item.payload['opportunity_kind']),
        isNot(contains('dream_pattern_check')),
      );

      final lowDreamOnly = radar.scan(
        snapshot: _snapshot(now, [
          _signal(
            NeuraSignalKind.dreamMood,
            value: 0.15,
            label: 'sad',
            evidence: [_evidence('dream-1', now)],
          ),
        ]),
        now: now,
      );
      expect(
        lowDreamOnly.map((item) => item.payload['opportunity_kind']),
        isNot(contains('dream_pattern_check')),
      );

      final both = radar.scan(
        snapshot: _snapshot(now, [
          _signal(
            NeuraSignalKind.mood,
            value: 0.15, // severity 0.85 -- above the 0.55 bar.
            evidence: [_evidence('mood-2', now)],
          ),
          _signal(
            NeuraSignalKind.dreamMood,
            value: 0.15, // sad-leaning valence -- at/below the 0.35 bar.
            label: 'sad',
            evidence: [_evidence('dream-2', now)],
          ),
        ]),
        now: now,
      );
      final dreamCandidate = both.singleWhere(
        (item) => item.payload['opportunity_kind'] == 'dream_pattern_check',
      );
      expect(
        dreamCandidate.capabilityId,
        NeuraCapabilityRegistry.openAppModule,
      );
      expect(dreamCandidate.body, contains('sad'));
      expect(dreamCandidate.evidence.map((e) => e.id), ['dream-2', 'mood-2']);
    });

    test('protects an active focus state from task nudges', () {
      final result = radar.scan(
        snapshot: _snapshot(now, [
          _signal(
            NeuraSignalKind.focus,
            value: 0.9,
            label: 'deepWork',
            evidence: [_evidence('focus-deep', now)],
          ),
          _signal(
            NeuraSignalKind.activeQuest,
            label: 'Write release notes',
            evidence: [_evidence('quest-notes', now)],
          ),
          _signal(
            NeuraSignalKind.questMomentum,
            value: 0.1,
            evidence: [_evidence('quest-momentum', now)],
          ),
          _signal(
            NeuraSignalKind.goal,
            label: 'Release Neura',
            evidence: [_evidence('goal-release', now)],
          ),
        ]),
        now: now,
      );

      expect(result, isEmpty);
    });

    test('uses stable ids independent of scan time and evidence order', () {
      final firstEvidence = _evidence('quest-a', now);
      final secondEvidence = _evidence('quest-b', now);

      NeuraIntelligenceSnapshot build(List<NeuraEvidenceRef> evidence) =>
          _snapshot(now, [
            _signal(
              NeuraSignalKind.activeQuest,
              label: 'Polish the dashboard',
              evidence: evidence,
            ),
            _signal(
              NeuraSignalKind.questMomentum,
              value: 0.05,
              evidence: [_evidence('momentum-a', now)],
            ),
          ]);

      final first = radar.scan(
        snapshot: build([firstEvidence, secondEvidence]),
        now: now,
      );
      final second = radar.scan(
        snapshot: build([secondEvidence, firstEvidence]),
        now: now.add(const Duration(minutes: 10)),
      );

      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(second.single.id, first.single.id);
      expect(first.single.id, startsWith('radar:quest_micro_step:'));
    });
  });
}

NeuraIntelligenceSnapshot _snapshot(
  DateTime generatedAt,
  List<NeuraFusedSignal> signals,
) =>
    NeuraIntelligenceSnapshot(generatedAt: generatedAt, signals: signals);

NeuraFusedSignal _signal(
  NeuraSignalKind kind, {
  double? value,
  String? label,
  double confidence = 0.9,
  required List<NeuraEvidenceRef> evidence,
}) =>
    NeuraFusedSignal(
      kind: kind,
      numericValue: value,
      label: label,
      confidence: confidence,
      evidence: evidence,
    );

NeuraEvidenceRef _evidence(String id, DateTime observedAt) => NeuraEvidenceRef(
      id: id,
      source: 'test',
      summary: 'Local test signal',
      observedAt: observedAt,
      confidence: 0.9,
      sensitivity: NeuraSensitivity.routine,
    );
