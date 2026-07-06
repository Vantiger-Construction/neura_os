import 'dart:convert';
import '../models/dream_entry.dart';
import '../../shared/services/self_heal_service.dart';
import '../../startup/neura_prefs_cache.dart';

class DreamService {
  DreamService._internal();
  static final DreamService instance = DreamService._internal();

  static const _keyDreams = 'neura_dream_entries_v1';

  final _selfHeal = SelfHealService.instance;

  Future<List<DreamEntry>> loadDreams() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_keyDreams);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final dreams = list
          .whereType<Map>()
          .map((m) => DreamEntry.fromMap(
                Map<String, dynamic>.from(m),
              ))
          .toList();
      dreams.sort((a, b) => b.date.compareTo(a.date));
      return dreams;
    } catch (e, st) {
      await _selfHeal.recordError('DreamService.loadDreams', e, st);
      await prefs.remove(_keyDreams);
      return [];
    }
  }

  Future<void> _saveDreams(List<DreamEntry> dreams) async {
    final prefs = NeuraPrefsCache.prefs;
    final list = dreams.map((d) => d.toMap()).toList();
    await prefs.setString(_keyDreams, jsonEncode(list));
  }

  Future<void> addOrUpdateDream(DreamEntry entry) async {
    final dreams = await loadDreams();
    final idx = dreams.indexWhere((d) => d.id == entry.id);
    if (idx >= 0) {
      dreams[idx] = entry;
    } else {
      dreams.add(entry);
    }
    await _saveDreams(dreams);
  }

  Future<void> deleteDream(String id) async {
    final dreams = await loadDreams();
    dreams.removeWhere((d) => d.id == id);
    await _saveDreams(dreams);
  }
}
