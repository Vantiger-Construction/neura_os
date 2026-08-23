enum NeuraBandwidthMode { recovery, simplified, balanced, deepFocus }

extension NeuraBandwidthModePresentation on NeuraBandwidthMode {
  String get label {
    return switch (this) {
      NeuraBandwidthMode.recovery => 'Recovery',
      NeuraBandwidthMode.simplified => 'Simplified',
      NeuraBandwidthMode.balanced => 'Balanced',
      NeuraBandwidthMode.deepFocus => 'Deep Focus',
    };
  }

  String get summary {
    return switch (this) {
      NeuraBandwidthMode.recovery =>
        'Reduce choices, protect attention, and suggest one safe next step.',
      NeuraBandwidthMode.simplified =>
        'Keep the plan short and move detail behind optional expansion.',
      NeuraBandwidthMode.balanced =>
        'Show a normal plan with clear approvals and explanations.',
      NeuraBandwidthMode.deepFocus =>
        'Protect the active outcome and queue unrelated interruptions.',
    };
  }
}

class NeuraCognitiveSignals {
  final double energy;
  final double focus;
  final double cognitiveLoad;
  final double urgency;
  final double taskSwitchRate;
  final double completionRate;
  final double notificationPressure;
  final int evidenceCount;
  final bool includesSelfReport;

  const NeuraCognitiveSignals({
    required this.energy,
    required this.focus,
    required this.cognitiveLoad,
    required this.urgency,
    required this.taskSwitchRate,
    required this.completionRate,
    required this.notificationPressure,
    this.evidenceCount = 7,
    this.includesSelfReport = true,
  });

  factory NeuraCognitiveSignals.defaults() {
    return const NeuraCognitiveSignals(
      energy: 0.58,
      focus: 0.55,
      cognitiveLoad: 0.42,
      urgency: 0.40,
      taskSwitchRate: 0.35,
      completionRate: 0.55,
      notificationPressure: 0.32,
    );
  }

  NeuraCognitiveSignals normalized() {
    return NeuraCognitiveSignals(
      energy: _unit(energy),
      focus: _unit(focus),
      cognitiveLoad: _unit(cognitiveLoad),
      urgency: _unit(urgency),
      taskSwitchRate: _unit(taskSwitchRate),
      completionRate: _unit(completionRate),
      notificationPressure: _unit(notificationPressure),
      evidenceCount: evidenceCount.clamp(0, 20).toInt(),
      includesSelfReport: includesSelfReport,
    );
  }

  NeuraCognitiveSignals copyWith({
    double? energy,
    double? focus,
    double? cognitiveLoad,
    double? urgency,
    double? taskSwitchRate,
    double? completionRate,
    double? notificationPressure,
    int? evidenceCount,
    bool? includesSelfReport,
  }) {
    return NeuraCognitiveSignals(
      energy: energy ?? this.energy,
      focus: focus ?? this.focus,
      cognitiveLoad: cognitiveLoad ?? this.cognitiveLoad,
      urgency: urgency ?? this.urgency,
      taskSwitchRate: taskSwitchRate ?? this.taskSwitchRate,
      completionRate: completionRate ?? this.completionRate,
      notificationPressure: notificationPressure ?? this.notificationPressure,
      evidenceCount: evidenceCount ?? this.evidenceCount,
      includesSelfReport: includesSelfReport ?? this.includesSelfReport,
    ).normalized();
  }

  static double _unit(double value) => value.clamp(0.0, 1.0).toDouble();
}

class NeuraCognitiveState {
  final double availableBandwidth;
  final double cognitiveLoad;
  final double energy;
  final double urgency;
  final double confidence;
  final NeuraBandwidthMode mode;
  final DateTime calculatedAt;
  final List<String> reasons;

  NeuraCognitiveState({
    required this.availableBandwidth,
    required this.cognitiveLoad,
    required this.energy,
    required this.urgency,
    required this.confidence,
    required this.mode,
    required this.calculatedAt,
    List<String> reasons = const <String>[],
  }) : reasons = List<String>.unmodifiable(reasons);
}
