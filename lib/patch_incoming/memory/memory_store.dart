import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'memory_models.dart';

/// Persists memory nodes to SharedPreferences.
class MemoryStore {
  static const _key = 'neura_memory_nodes_v1';

  Future<List<MemoryNode>> load() async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    final list = nodes.map((n) => n.toMap()).toList();
    await prefs.setString(_key, json.encode(list));
  }
}
