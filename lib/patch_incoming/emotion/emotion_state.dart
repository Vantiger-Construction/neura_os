/// Represents a point-in-time emotional state.
class EmotionState {
  final double valence; // -1.0 (negative) to 1.0 (positive)
  final double arousal; // 0.0 (calm) to 1.0 (excited)
  final double stress; // 0.0 (relaxed) to 1.0 (stressed)
  final DateTime timestamp;

  const EmotionState({
    this.valence = 0.0,
    this.arousal = 0.5,
    this.stress = 0.0,
    required this.timestamp,
  });

  EmotionState copyWith({
    double? valence,
    double? arousal,
    double? stress,
    DateTime? timestamp,
  }) {
    return EmotionState(
      valence: valence ?? this.valence,
      arousal: arousal ?? this.arousal,
      stress: stress ?? this.stress,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toMap() => {
    'valence': valence,
    'arousal': arousal,
    'stress': stress,
    'timestamp': timestamp.toIso8601String(),
  };

  factory EmotionState.fromMap(Map<String, dynamic> map) {
    return EmotionState(
      valence: (map['valence'] as num?)?.toDouble() ?? 0.0,
      arousal: (map['arousal'] as num?)?.toDouble() ?? 0.5,
      stress: (map['stress'] as num?)?.toDouble() ?? 0.0,
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
