import 'emotion_state.dart';

/// Analyzes text input to infer an emotional state.
class EmotionAnalyzer {
  /// Simple keyword-based emotion inference.
  EmotionState analyze(String text) {
    final lower = text.toLowerCase();
    double valence = 0.0;
    double arousal = 0.5;
    double stress = 0.0;

    if (lower.contains('happy') ||
        lower.contains('joy') ||
        lower.contains('great')) {
      valence = 0.7;
    }
    if (lower.contains('sad') ||
        lower.contains('cry') ||
        lower.contains('hurt')) {
      valence = -0.6;
    }
    if (lower.contains('angry') || lower.contains('furious')) {
      valence = -0.5;
      arousal = 0.9;
    }
    if (lower.contains('stressed') ||
        lower.contains('overwhelmed') ||
        lower.contains('anxious')) {
      stress = 0.8;
      arousal = 0.7;
    }
    if (lower.contains('calm') ||
        lower.contains('peaceful') ||
        lower.contains('relaxed')) {
      stress = 0.1;
      arousal = 0.2;
      if (valence == 0.0) valence = 0.3;
    }

    return EmotionState(
      valence: valence,
      arousal: arousal,
      stress: stress,
      timestamp: DateTime.now(),
    );
  }
}
