/// Represents the current emotional state
class EmotionState {
  final Map<String, double> emotions;
  final DateTime timestamp;
  
  EmotionState({
    required this.emotions,
    required this.timestamp,
  });
  
  factory EmotionState.neutral() {
    return EmotionState(
      emotions: {
        'joy': 0.5,
        'sadness': 0.0,
        'anger': 0.0,
        'fear': 0.0,
        'energy': 0.5,
        'mood': 0.5,
      },
      timestamp: DateTime.now(),
    );
  }
  
  double get mood => emotions['mood'] ?? 0.5;
  double get energy => emotions['energy'] ?? 0.5;
}
