import '../../shared/services/self_heal_service.dart';
import '../../startup/neura_prefs_cache.dart';

class MoodStateService {
  MoodStateService._internal();
  static final MoodStateService instance = MoodStateService._internal();

  static const _keyMood = 'neura_current_mood_v1';

  final _selfHeal = SelfHealService.instance;

  String _mood = 'neutral';
  String get currentMood => _mood;

  Future<void> load() async {
    try {
      final prefs = NeuraPrefsCache.prefs;
      _mood = prefs.getString(_keyMood) ?? 'neutral';
    } catch (e, st) {
      await _selfHeal.recordError('MoodStateService.load', e, st);
      _mood = 'neutral';
    }
  }

  Future<void> setMood(String mood) async {
    _mood = mood;
    try {
      final prefs = NeuraPrefsCache.prefs;
      await prefs.setString(_keyMood, mood);
    } catch (e, st) {
      await _selfHeal.recordError('MoodStateService.setMood', e, st);
    }
  }

  void resetAfterDataWipe() {
    _mood = 'neutral';
  }
}
