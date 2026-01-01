import 'dart:convert';

import 'persona_profile.dart';

enum NeuraThemePref {
  system,
  dark,
  light,
}

class HumanPrefs {
  final NeuraThemePref theme;
  final bool highContrast;
  final bool reducedMotion;
  final bool lowStim;
  final bool safeMode;
  final double textScale;
  final bool allowLearning; // Whether Neura is allowed to learn locally from usage.

  /// Neura Coach (local reflections)
  final bool coachEnabled;
  final bool coachPopups;

  final PersonaProfile persona;

  const HumanPrefs({
    required this.theme,
    required this.highContrast,
    required this.reducedMotion,
    required this.lowStim,
    required this.safeMode,
    required this.textScale,
    required this.allowLearning,
    required this.coachEnabled,
    required this.coachPopups,
    required this.persona,
  });

  HumanPrefs copyWith({
    NeuraThemePref? theme,
    bool? highContrast,
    bool? reducedMotion,
    bool? lowStim,
    bool? safeMode,
    double? textScale,
    bool? allowLearning,
    bool? coachEnabled,
    bool? coachPopups,
    PersonaProfile? persona,
  }) {
    return HumanPrefs(
      theme: theme ?? this.theme,
      highContrast: highContrast ?? this.highContrast,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      lowStim: lowStim ?? this.lowStim,
      safeMode: safeMode ?? this.safeMode,
      textScale: textScale ?? this.textScale,
      allowLearning: allowLearning ?? this.allowLearning,
      coachEnabled: coachEnabled ?? this.coachEnabled,
      coachPopups: coachPopups ?? this.coachPopups,
      persona: persona ?? this.persona,
    );
  }

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'highContrast': highContrast,
        'reducedMotion': reducedMotion,
        'lowStim': lowStim,
        'safeMode': safeMode,
        'textScale': textScale,
        'allowLearning': allowLearning,
        'coachEnabled': coachEnabled,
        'coachPopups': coachPopups,
        'persona': persona.toJson(),
      };

  static HumanPrefs fromJson(Map<String, dynamic> json) {
    final themeRaw = (json['theme'] as String?) ?? 'system';
    final theme = NeuraThemePref.values.firstWhere(
      (e) => e.name == themeRaw,
      orElse: () => NeuraThemePref.system,
    );

    final ts = json['textScale'];
    final textScale = (ts is num ? ts.toDouble() : 1.0).clamp(0.85, 1.35);

    final personaRaw = json['persona'];
    PersonaProfile persona;
    if (personaRaw is Map<String, dynamic>) {
      persona = PersonaProfile.fromJson(personaRaw);
    } else {
      persona = PersonaProfile.defaults;
    }

    return HumanPrefs(
      theme: theme,
      highContrast: (json['highContrast'] as bool?) ?? false,
      reducedMotion: (json['reducedMotion'] as bool?) ?? false,
      lowStim: (json['lowStim'] as bool?) ?? false,
      safeMode: (json['safeMode'] as bool?) ?? false,
      textScale: textScale,
      allowLearning: (json['allowLearning'] as bool?) ?? true,
      coachEnabled: (json['coachEnabled'] as bool?) ?? true,
      coachPopups: (json['coachPopups'] as bool?) ?? true,
      persona: persona,
    );
  }

  static const defaults = HumanPrefs(
    theme: NeuraThemePref.system,
    highContrast: false,
    reducedMotion: false,
    lowStim: false,
    safeMode: false,
    textScale: 1.0,
    allowLearning: true,
    coachEnabled: true,
    coachPopups: true,
    persona: PersonaProfile.defaults,
  );

  String toJsonString() => jsonEncode(toJson());

  static HumanPrefs fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } catch (_) {}
    return HumanPrefs.defaults;
  }
}
