import 'dart:convert';

/// Tiny local "what worked for me" store.
///
/// This is *not* surveillance and it never leaves the device.
import '../../startup/neura_prefs_cache.dart';

class LearningStore {
  LearningStore._();
  static final LearningStore instance = LearningStore._();

  static const _key = 'neura.human.learning.v1';

  Future<Map<String, int>> _read() async {
    final sp = NeuraPrefsCache.prefs;
    final raw = sp.getString(_key);
    if (raw == null || raw.trim().isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, int>{};
        decoded.forEach((k, v) {
          if (k == null) return;
          final key = k.toString();
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
          if (n > 0) out[key] = n;
        });
        return out;
      }
    } catch (_) {}
    return <String, int>{};
  }

  Future<void> _write(Map<String, int> m) async {
    final sp = NeuraPrefsCache.prefs;
    await sp.setString(_key, jsonEncode(m));
  }

  Future<void> markHelpful(String id) async {
    final m = await _read();
    m[id] = (m[id] ?? 0) + 1;
    await _write(m);
  }

  Future<List<MapEntry<String, int>>> top({int max = 5}) async {
    final m = await _read();
    final list = m.entries.toList(growable: false);
    list.sort((a, b) => b.value.compareTo(a.value));
    if (list.length <= max) return list;
    return list.sublist(0, max);
  }

  Future<void> clear() async {
    final sp = NeuraPrefsCache.prefs;
    await sp.remove(_key);
  }
}
