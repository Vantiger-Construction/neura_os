enum NeuraIntent { seekingCalm, seekingProgress, seekingSleep, seekingConnection }

class IntentVector {
  final Map<NeuraIntent, double> scores;
  const IntentVector(this.scores);

  NeuraIntent get topIntent {
    return scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
