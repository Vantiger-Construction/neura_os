class DistressSignal {
  final bool active;
  final List<String> reasons;

  DistressSignal({required this.active, this.reasons = const []});
}

class DistressDetector {
  const DistressDetector({this.activationThreshold = 3})
      : assert(activationThreshold > 0);

  /// Minimum weighted evidence required before [detect] reports active
  /// distress. High-impact consumers retain the conservative default.
  final int activationThreshold;

  DistressSignal detect({
    required List<int> recentMoods,
    required int appOpensLastHour,
    required bool lotsOfNegativeWords,
  }) {
    final reasons = <String>[];
    var score = 0;

    if (recentMoods.length >= 3 &&
        recentMoods.sublist(recentMoods.length - 3).every((m) => m <= -1)) {
      score += 2;
      reasons.add('Several recent moods have been low.');
    }
    if (appOpensLastHour >= 4) {
      score += 1;
      reasons.add('You opened Neura multiple times in a short window.');
    }
    if (lotsOfNegativeWords) {
      score += 2;
      reasons.add('Recent text contains a lot of distress language.');
    }

    return DistressSignal(
      active: score >= activationThreshold,
      reasons: reasons,
    );
  }
}
