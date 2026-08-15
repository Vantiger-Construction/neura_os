import 'dart:convert';
/// Web-safe AppLog implementation using SharedPreferences.
///
/// Stores NDJSON inside a single key. We keep a bounded tail so storage doesn't balloon.
import '../../startup/neura_prefs_cache.dart';

class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const _key = 'neura_log_ndjson';
  bool _init = false;
  bool _suspendedForDataWipe = false;

  Future<void> init() async {
    if (_suspendedForDataWipe) return;
    if (_init) return;
    _init = true;
    await info('log_init', {'platform': 'web'});
  }

  Future<void> info(String event,
      [Map<String, Object?> data = const {}]) async {
    await _write('info', event, data);
  }

  Future<void> warn(String event,
      [Map<String, Object?> data = const {}]) async {
    await _write('warn', event, data);
  }

  Future<void> error(String event,
      [Map<String, Object?> data = const {}]) async {
    await _write('error', event, data);
  }

  Future<void> _write(
      String level, String event, Map<String, Object?> data) async {
    if (_suspendedForDataWipe) return;
    try {
      final prefs = NeuraPrefsCache.prefs;
      final current = prefs.getString(_key) ?? '';
      final payload = <String, Object?>{
        'ts': DateTime.now().toUtc().toIso8601String(),
        'level': level,
        'event': event,
        'data': data,
      };
      final next = '${current.isEmpty ? '' : current}${jsonEncode(payload)}\n';

      // Keep last ~200 lines. Cheap and effective.
      final lines = const LineSplitter().convert(next);
      final trimmed =
          lines.length <= 220 ? lines : lines.sublist(lines.length - 220);
      await prefs.setString(
          _key, trimmed.join('\n') + (trimmed.isEmpty ? '' : '\n'));
    } catch (_) {
      // If logging fails, do not crash.
    }
  }

  Future<List<String>> tail({int maxLines = 200}) async {
    try {
      final prefs = NeuraPrefsCache.prefs;
      final current = prefs.getString(_key) ?? '';
      if (current.trim().isEmpty) return const [];
      final lines = const LineSplitter().convert(current.trimRight());
      if (lines.length <= maxLines) return lines;
      return lines.sublist(lines.length - maxLines);
    } catch (_) {
      return const [];
    }
  }

  Future<void> clear() async {
    try {
      final prefs = NeuraPrefsCache.prefs;
      await prefs.remove(_key);
    } catch (_) {
      // shrug
    }
  }

  Future<void> resetAfterDataWipe() async {
    _suspendedForDataWipe = true;
    await clear();
    _init = false;
  }
}
