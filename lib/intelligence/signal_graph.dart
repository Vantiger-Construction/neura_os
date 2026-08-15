import 'dart:math';

import 'models.dart';

/// Fuses short-lived, privacy-labelled observations into an explainable local
/// snapshot. Raw journal, therapy, dream, or legacy text is never required.
class NeuraSignalGraph {
  const NeuraSignalGraph();

  static const _futureTolerance = Duration(minutes: 5);
  static const _maxEvidencePerSignal = 5;

  NeuraIntelligenceSnapshot fuse({
    required Iterable<NeuraSignalObservation> observations,
    required DateTime now,
    bool allowSensitiveSignals = false,
  }) {
    final groups = <NeuraSignalKind, List<_WeightedObservation>>{};

    for (final observation in observations) {
      if (observation.validFor <= Duration.zero) continue;
      if (observation.observedAt.isAfter(now.add(_futureTolerance))) continue;
      if (observation.isExpiredAt(now)) continue;
      if (!allowSensitiveSignals &&
          observation.sensitivity == NeuraSensitivity.sensitive) {
        continue;
      }

      final age = max(0, now.difference(observation.observedAt).inMilliseconds);
      final lifetime = max(1, observation.validFor.inMilliseconds);
      final ageRatio = (age / lifetime).clamp(0.0, 1.0);
      final freshness = 1 - (ageRatio * 0.65);
      final weight = observation.confidence * freshness;
      if (weight <= 0) continue;

      groups
          .putIfAbsent(observation.kind, () => [])
          .add(_WeightedObservation(observation, weight));
    }

    final fused = <NeuraFusedSignal>[];
    for (final entry in groups.entries) {
      final items = entry.value
        ..sort((a, b) {
          final byWeight = b.weight.compareTo(a.weight);
          return byWeight != 0
              ? byWeight
              : a.observation.id.compareTo(b.observation.id);
        });
      final numeric = items
          .where((item) => item.observation.numericValue != null)
          .toList(growable: false);

      double? value;
      var conflictPenalty = 1.0;
      if (numeric.isNotEmpty) {
        var weightedSum = 0.0;
        var totalWeight = 0.0;
        var minimum = double.infinity;
        var maximum = double.negativeInfinity;
        for (final item in numeric) {
          final current = item.observation.numericValue!;
          weightedSum += current * item.weight;
          totalWeight += item.weight;
          minimum = min(minimum, current);
          maximum = max(maximum, current);
        }
        value = totalWeight == 0 ? null : weightedSum / totalWeight;
        final spread = (maximum - minimum).abs().clamp(0.0, 1.0);
        conflictPenalty = 1 - (spread * 0.45);
      }

      final averageWeight = items
              .map((item) => item.weight)
              .fold<double>(0, (sum, weight) => sum + weight) /
          items.length;
      final confidence =
          (averageWeight * conflictPenalty).clamp(0.0, 1.0).toDouble();
      final labelled = items.where(
        (item) => item.observation.label?.trim().isNotEmpty == true,
      );
      final label = labelled.isEmpty ? null : labelled.first.observation.label;

      fused.add(
        NeuraFusedSignal(
          kind: entry.key,
          numericValue: value,
          label: label,
          confidence: confidence,
          evidence: List.unmodifiable(
            items.take(_maxEvidencePerSignal).map(
                  (item) => NeuraEvidenceRef(
                    id: item.observation.id,
                    source: item.observation.source,
                    summary: item.observation.summary,
                    observedAt: item.observation.observedAt,
                    confidence: item.weight.clamp(0.0, 1.0).toDouble(),
                    sensitivity: item.observation.sensitivity,
                  ),
                ),
          ),
        ),
      );
    }

    return NeuraIntelligenceSnapshot(generatedAt: now, signals: fused);
  }
}

class _WeightedObservation {
  const _WeightedObservation(this.observation, this.weight);

  final NeuraSignalObservation observation;
  final double weight;
}
