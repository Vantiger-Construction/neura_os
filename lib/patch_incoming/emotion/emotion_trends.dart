import 'emotion_state.dart';

/// Computes trends over a list of emotion states.
class EmotionTrends {
  /// Average valence over the given states.
  double averageValence(List<EmotionState> states) {
    if (states.isEmpty) return 0.0;
    return states.map((s) => s.valence).reduce((a, b) => a + b) / states.length;
  }

  /// Average stress over the given states.
  double averageStress(List<EmotionState> states) {
    if (states.isEmpty) return 0.0;
    return states.map((s) => s.stress).reduce((a, b) => a + b) / states.length;
  }

  /// Simple trend direction: positive, negative, or neutral.
  String trendDirection(List<EmotionState> states) {
    if (states.length < 2) return 'neutral';
    final sorted = [...states]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final first = sorted.first.valence;
    final last = sorted.last.valence;
    final diff = last - first;
    if (diff > 0.2) return 'positive';
    if (diff < -0.2) return 'negative';
    return 'neutral';
  }
}
