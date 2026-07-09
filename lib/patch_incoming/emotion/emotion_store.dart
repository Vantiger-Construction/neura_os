import 'dart:convert';
import 'emotion_state.dart';
/// Persists emotion snapshots to SharedPreferences.
import '../../startup/neura_prefs_cache.dart';

class EmotionStore {
  static const _key = 'neura_emotion_history_v1';

  Future<List<EmotionState>> load() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = json.decode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => EmotionState.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<EmotionState> states) async {
    final prefs = NeuraPrefsCache.prefs;
    final list = states.map((s) => s.toMap()).toList();
    await prefs.setString(_key, json.encode(list));
  }

  Future<void> append(EmotionState state) async {
    final states = await load();
    states.add(state);
    await save(states);
  }
}
