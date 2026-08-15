class EmotionAnalysisService {
  static const _moods = <String, List<String>>{
    'joy': [
      'happy',
      'great',
      'excited',
      'amazing',
      'wonderful',
      'love',
      'glad',
      'fantastic',
      'joyful'
    ],
    'sadness': [
      'sad',
      'unhappy',
      'cry',
      'depressed',
      'down',
      'grief',
      'miss',
      'alone',
      'hopeless'
    ],
    'anger': [
      'angry',
      'furious',
      'mad',
      'frustrated',
      'annoyed',
      'rage',
      'hate',
      'irritated'
    ],
    'fear': [
      'scared',
      'afraid',
      'anxious',
      'worried',
      'nervous',
      'dread',
      'panic',
      'terrified'
    ],
    'calm': [
      'calm',
      'peaceful',
      'relaxed',
      'serene',
      'content',
      'okay',
      'fine',
      'good'
    ],
    'surprise': [
      'surprised',
      'shocked',
      'astonished',
      'unexpected',
      'wow',
      'sudden'
    ],
  };

  /// Analyses [text] and returns the dominant mood tag.
  /// Returns 'neutral' when no strong signal is found.
  Future<String> analyzeEmotion(String text) async {
    if (text.trim().isEmpty) return 'neutral';
    final lower = text.toLowerCase();
    final scores = <String, int>{};
    for (final entry in _moods.entries) {
      scores[entry.key] =
          entry.value.fold(0, (sum, kw) => sum + (lower.contains(kw) ? 1 : 0));
    }
    final best = scores.entries
        .where((e) => e.value > 0)
        .fold<MapEntry<String, int>?>(null, (prev, e) {
      if (prev == null || e.value > prev.value) return e;
      return prev;
    });
    return best?.key ?? 'neutral';
  }
}
