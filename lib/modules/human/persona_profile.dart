import 'dart:convert';

/// Neura's per-user style knobs.
///
/// This is intentionally lightweight and local-only.
class PersonaProfile {
  final double directness; // 0 gentle -> 1 blunt
  final double humor; // 0 serious -> 1 jokey
  final double energy; // 0 calm -> 1 hype
  final double depth; // 0 simple -> 1 philosophical
  final double pacing; // 0 slow -> 1 fast

  final List<String> goals;
  final List<String> values;

  const PersonaProfile({
    required this.directness,
    required this.humor,
    required this.energy,
    required this.depth,
    required this.pacing,
    required this.goals,
    required this.values,
  });

  PersonaProfile copyWith({
    double? directness,
    double? humor,
    double? energy,
    double? depth,
    double? pacing,
    List<String>? goals,
    List<String>? values,
  }) {
    return PersonaProfile(
      directness: directness ?? this.directness,
      humor: humor ?? this.humor,
      energy: energy ?? this.energy,
      depth: depth ?? this.depth,
      pacing: pacing ?? this.pacing,
      goals: goals ?? this.goals,
      values: values ?? this.values,
    );
  }

  Map<String, dynamic> toJson() => {
        'directness': directness,
        'humor': humor,
        'energy': energy,
        'depth': depth,
        'pacing': pacing,
        'goals': goals,
        'values': values,
      };

  static PersonaProfile fromJson(Map<String, dynamic> json) {
    double d(String k, double def) {
      final v = json[k];
      if (v is num) return v.toDouble().clamp(0.0, 1.0);
      return def;
    }

    List<String> list(String k) {
      final v = json[k];
      if (v is List) {
        return v
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList(growable: true);
      }
      return <String>[];
    }

    return PersonaProfile(
      directness: d('directness', 0.55),
      humor: d('humor', 0.55),
      energy: d('energy', 0.45),
      depth: d('depth', 0.55),
      pacing: d('pacing', 0.55),
      goals: list('goals'),
      values: list('values'),
    );
  }

  static const defaults = PersonaProfile(
    directness: 0.55,
    humor: 0.55,
    energy: 0.45,
    depth: 0.55,
    pacing: 0.55,
    goals: <String>[],
    values: <String>[],
  );

  String toJsonString() => jsonEncode(toJson());

  static PersonaProfile fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } catch (_) {}
    return PersonaProfile.defaults;
  }
}
