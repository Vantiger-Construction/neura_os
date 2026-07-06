import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/persona_profile.dart';
import '../../shared/services/self_heal_service.dart';
import '../../startup/neura_prefs_cache.dart';

class NeuraPersonaService extends ChangeNotifier {
  NeuraPersonaService._internal();
  static final NeuraPersonaService instance = NeuraPersonaService._internal();

  static const _keyPersona = 'neura_persona_profile_v1';

  final _selfHeal = SelfHealService.instance;

  PersonaProfile _current = PersonaProfile.neutral();
  PersonaProfile get current => _current;

  Future<void> load() async {
    try {
      final prefs = NeuraPrefsCache.prefs;
      final raw = prefs.getString(_keyPersona);
      if (raw == null) {
        _current = PersonaProfile.neutral();
      } else {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _current = PersonaProfile.fromMap(map);
      }
    } catch (e, st) {
      await _selfHeal.recordError('NeuraPersonaService.load', e, st);
      _current = PersonaProfile.neutral();
    }
    notifyListeners();
  }

  Future<void> update(PersonaProfile profile) async {
    _current = profile;
    notifyListeners();
    try {
      final prefs = NeuraPrefsCache.prefs;
      await prefs.setString(
        _keyPersona,
        jsonEncode(profile.toMap()),
      );
    } catch (e, st) {
      await _selfHeal.recordError('NeuraPersonaService.update', e, st);
    }
  }

  /// Helper to generate a short description for UI preview.
  String describePersona(PersonaProfile p) {
    final tone = p.warmth >= 0.7
        ? 'soft and caring'
        : (p.directness >= 0.7 ? 'direct and no-nonsense' : 'balanced');
    final vibe = p.energy >= 0.7
        ? 'high-energy hype coach'
        : (p.energy <= 0.3 ? 'calm, low-and-slow' : 'steady and focused');
    final jokes = p.humor >= 0.7
        ? 'sprinkles in jokes a lot'
        : (p.humor <= 0.3 ? 'keeps things pretty serious' : 'uses light humor');
    final depth =
        p.depth >= 0.7 ? 'goes deep into meaning' : 'keeps advice practical';

    return 'Neura will feel $tone, like a $vibe, who $jokes and $depth.';
  }
}
