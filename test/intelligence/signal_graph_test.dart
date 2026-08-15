import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/intelligence/signal_graph.dart';

void main() {
  final now = DateTime.utc(2026, 8, 14, 18);
  const graph = NeuraSignalGraph();

  group('NeuraSignalGraph filtering', () {
    test('drops expired and far-future observations', () {
      final snapshot = graph.fuse(
        now: now,
        observations: [
          _observation(
            id: 'expired-mood',
            kind: NeuraSignalKind.mood,
            observedAt: now.subtract(const Duration(hours: 2)),
            validFor: const Duration(hours: 1),
            numericValue: 0.2,
          ),
          _observation(
            id: 'future-energy',
            kind: NeuraSignalKind.energy,
            observedAt: now.add(const Duration(minutes: 6)),
            numericValue: 0.8,
          ),
          _observation(
            id: 'current-goal',
            kind: NeuraSignalKind.goal,
            observedAt: now,
            label: 'Finish Neura 1.3',
          ),
        ],
      );

      expect(snapshot.signal(NeuraSignalKind.mood), isNull);
      expect(snapshot.signal(NeuraSignalKind.energy), isNull);
      expect(snapshot.label(NeuraSignalKind.goal), 'Finish Neura 1.3');
    });

    test('excludes sensitive observations unless explicitly allowed', () {
      final observations = [
        _observation(
          id: 'routine-mood',
          kind: NeuraSignalKind.mood,
          observedAt: now,
          numericValue: 0.6,
        ),
        _observation(
          id: 'sensitive-mood',
          kind: NeuraSignalKind.mood,
          observedAt: now,
          numericValue: 0.2,
          sensitivity: NeuraSensitivity.sensitive,
        ),
      ];

      final privateByDefault = graph.fuse(
        observations: observations,
        now: now,
      );
      final explicitlyAllowed = graph.fuse(
        observations: observations,
        now: now,
        allowSensitiveSignals: true,
      );

      expect(
        privateByDefault
            .signal(NeuraSignalKind.mood)!
            .evidence
            .map((item) => item.id),
        ['routine-mood'],
      );
      expect(
        explicitlyAllowed
            .signal(NeuraSignalKind.mood)!
            .evidence
            .map((item) => item.id)
            .toSet(),
        {'routine-mood', 'sensitive-mood'},
      );
    });
  });

  group('NeuraSignalGraph fusion', () {
    test('reduces confidence when numeric observations conflict', () {
      final conflicting = graph.fuse(
        observations: [
          _observation(
            id: 'mood-low',
            kind: NeuraSignalKind.mood,
            observedAt: now,
            numericValue: 0,
          ),
          _observation(
            id: 'mood-high',
            kind: NeuraSignalKind.mood,
            observedAt: now,
            numericValue: 1,
          ),
        ],
        now: now,
      ).signal(NeuraSignalKind.mood)!;

      final aligned = graph.fuse(
        observations: [
          _observation(
            id: 'mood-a',
            kind: NeuraSignalKind.mood,
            observedAt: now,
            numericValue: 0.5,
          ),
          _observation(
            id: 'mood-b',
            kind: NeuraSignalKind.mood,
            observedAt: now,
            numericValue: 0.5,
          ),
        ],
        now: now,
      ).signal(NeuraSignalKind.mood)!;

      expect(conflicting.numericValue, closeTo(0.5, 0.000001));
      expect(conflicting.confidence, closeTo(0.55, 0.000001));
      expect(conflicting.confidence, lessThan(aligned.confidence));
      expect(aligned.confidence, closeTo(1, 0.000001));
    });

    test('produces the same fusion independent of observation order', () {
      final observations = [
        _observation(
          id: 'energy-primary',
          kind: NeuraSignalKind.energy,
          observedAt: now,
          numericValue: 0.8,
          label: 'energized',
          confidence: 0.9,
        ),
        _observation(
          id: 'energy-secondary',
          kind: NeuraSignalKind.energy,
          observedAt: now.subtract(const Duration(hours: 2)),
          numericValue: 0.2,
          label: 'tired',
          confidence: 0.6,
        ),
      ];

      final forward = graph
          .fuse(
            observations: observations,
            now: now,
          )
          .signal(NeuraSignalKind.energy)!;
      final reversed = graph
          .fuse(
            observations: observations.reversed,
            now: now,
          )
          .signal(NeuraSignalKind.energy)!;

      expect(reversed.numericValue, closeTo(forward.numericValue!, 0.000001));
      expect(reversed.confidence, closeTo(forward.confidence, 0.000001));
      expect(reversed.label, forward.label);
      expect(
        reversed.evidence.map((item) => item.id),
        forward.evidence.map((item) => item.id),
      );
    });
  });
}

NeuraSignalObservation _observation({
  required String id,
  required NeuraSignalKind kind,
  required DateTime observedAt,
  double? numericValue,
  String? label,
  double confidence = 1,
  NeuraSensitivity sensitivity = NeuraSensitivity.routine,
  Duration validFor = const Duration(days: 1),
}) =>
    NeuraSignalObservation(
      id: id,
      kind: kind,
      source: 'test',
      summary: 'Deterministic local test signal',
      observedAt: observedAt,
      numericValue: numericValue,
      label: label,
      confidence: confidence,
      sensitivity: sensitivity,
      validFor: validFor,
    );
