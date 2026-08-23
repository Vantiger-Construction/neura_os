import 'dart:math' as math;

import 'neura_cognitive_state.dart';

class NeuraBandwidthEngine {
  const NeuraBandwidthEngine();

  NeuraCognitiveState estimate(
    NeuraCognitiveSignals signals, {
    bool safeMode = false,
    DateTime? calculatedAt,
  }) {
    final energy = _clamp01(signals.energy);
    final focus = _clamp01(signals.focus);
    final reportedLoad = _clamp01(signals.cognitiveLoad);
    final urgency = _clamp01(signals.urgency);
    final switchRate = _clamp01(signals.taskSwitchRate);
    final completionRate = _clamp01(signals.completionRate);
    final notificationPressure = _clamp01(signals.notificationPressure);

    final strain = _clamp01(
      reportedLoad * 0.40 +
          switchRate * 0.18 +
          notificationPressure * 0.16 +
          (1 - completionRate) * 0.14 +
          urgency * 0.12,
    );
    final resources = _clamp01(
      energy * 0.55 + focus * 0.30 + completionRate * 0.15,
    );
    final bandwidth = _clamp01(resources * (1 - strain * 0.65));
    final confidence = _clamp01(
      0.34 +
          math.min(signals.evidenceCount, 6).toDouble() * 0.07 +
          (signals.includesSelfReport ? 0.18 : 0),
    );

    final mode = _selectMode(
      safeMode: safeMode,
      bandwidth: bandwidth,
      strain: strain,
      focus: focus,
    );

    return NeuraCognitiveState(
      availableBandwidth: bandwidth,
      cognitiveLoad: strain,
      energy: energy,
      urgency: urgency,
      confidence: confidence,
      mode: mode,
      calculatedAt: calculatedAt ?? DateTime.now().toUtc(),
      reasons: _explain(
        safeMode: safeMode,
        bandwidth: bandwidth,
        strain: strain,
        energy: energy,
        focus: focus,
        switchRate: switchRate,
        notificationPressure: notificationPressure,
      ),
    );
  }

  NeuraBandwidthMode _selectMode({
    required bool safeMode,
    required double bandwidth,
    required double strain,
    required double focus,
  }) {
    if (safeMode || strain >= 0.82 || bandwidth < 0.27) {
      return NeuraBandwidthMode.recovery;
    }
    if (bandwidth < 0.49) {
      return NeuraBandwidthMode.simplified;
    }
    if (bandwidth >= 0.72 && focus >= 0.65 && strain < 0.48) {
      return NeuraBandwidthMode.deepFocus;
    }
    return NeuraBandwidthMode.balanced;
  }

  List<String> _explain({
    required bool safeMode,
    required double bandwidth,
    required double strain,
    required double energy,
    required double focus,
    required double switchRate,
    required double notificationPressure,
  }) {
    final reasons = <String>[];

    if (safeMode) {
      reasons.add('Safe Mode forces the most conservative local-only state.');
    }
    if (strain >= 0.68) {
      reasons.add('Current load signals indicate elevated mental pressure.');
    } else if (strain <= 0.35) {
      reasons.add('Current load signals are relatively light.');
    }
    if (energy < 0.35) {
      reasons.add('Low available energy favors shorter, easier actions.');
    } else if (energy > 0.72) {
      reasons.add('Energy is high enough to support a more complete plan.');
    }
    if (focus >= 0.70) {
      reasons.add('Focus is strong enough to protect a deeper work block.');
    }
    if (switchRate >= 0.65) {
      reasons.add('Frequent task switching favors fewer visible choices.');
    }
    if (notificationPressure >= 0.65) {
      reasons.add('Notification pressure should be reduced before adding work.');
    }
    if (reasons.isEmpty) {
      reasons.add(
        bandwidth >= 0.50
            ? 'Signals support a normal, explainable action plan.'
            : 'Signals favor a shorter plan with reduced information density.',
      );
    }
    return reasons;
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();
}
