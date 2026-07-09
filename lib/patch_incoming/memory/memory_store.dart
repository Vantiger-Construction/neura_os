import 'dart:convert';
import 'memory_models.dart';
/// Persists memory nodes to SharedPreferences.
import '../../startup/neura_prefs_cache.dart';

class MemoryStore {
  static const _key = 'neura_memory_nodes_v1';

  Future<List<MemoryNode>> load() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = json.decode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => MemoryNode.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<MemoryNode> nodes) async {
    final prefs = NeuraPrefsCache.prefs;
    final list = nodes.map((n) => n.toMap()).toList();
    await prefs.setString(_key, json.encode(list));
  }
}
