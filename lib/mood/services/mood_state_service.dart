import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/services/self_heal_service.dart';

class MoodStateService {
  MoodStateService._internal();
  static final MoodStateService instance = MoodStateService._internal();

  static const _keyMood = 'neura_current_mood_v1';

  final _selfHeal = SelfHealService.instance;

  String _mood = 'neutral';
  String get currentMood => _mood;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mood = prefs.getString(_keyMood) ?? 'neutral';
    } catch (e, st) {
      await _selfHeal.recordError('MoodStateService.load', e, st);
      _mood = 'neutral';
    }
  }

  Future<void> setMood(String mood) async {
    _mood = mood;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMood, mood);
    } catch (e, st) {
      await _selfHeal.recordError('MoodStateService.setMood', e, st);
    }
  }
}
