import 'package:flutter/foundation.dart';

@immutable
class PersonaProfile {
  final double warmth;      // how caring / soft Neura sounds
  final double directness;  // how blunt vs gentle
  final double humor;       // how often she jokes
  final double energy;      // calm vs hyped
  final double depth;       // surface tips vs deep reflections;

  const PersonaProfile({
    required this.warmth,
    required this.directness,
    required this.humor,
    required this.energy,
    required this.depth,
  });

  factory PersonaProfile.neutral() {
    return const PersonaProfile(
      warmth: 0.6,
      directness: 0.5,
      humor: 0.5,
      energy: 0.5,
      depth: 0.5,
    );
  }

  PersonaProfile copyWith({
    double? warmth,
    double? directness,
    double? humor,
    double? energy,
    double? depth,
  }) {
    return PersonaProfile(
      warmth: warmth ?? this.warmth,
      directness: directness ?? this.directness,
      humor: humor ?? this.humor,
      energy: energy ?? this.energy,
      depth: depth ?? this.depth,
    );
  }

  Map<String, dynamic> toMap() => {
        'warmth': warmth,
        'directness': directness,
        'humor': humor,
        'energy': energy,
        'depth': depth,
      };

  factory PersonaProfile.fromMap(Map<String, dynamic> map) {
    double _d(String key, double fallback) {
      final v = map[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    return PersonaProfile(
      warmth: _d('warmth', 0.6),
      directness: _d('directness', 0.5),
      humor: _d('humor', 0.5),
      energy: _d('energy', 0.5),
      depth: _d('depth', 0.5),
    );
  }
}
