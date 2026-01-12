import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny persistent log for Neura OS.
///
/// Stores newline-delimited JSON (NDJSON) so one bad line doesn't brick the whole log.
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  File? _file;
  bool _init = false;

  Future<void> init() async {
    if (_init) return;
    _init = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}/neura');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _file = File('${logDir.path}/neura.log.ndjson');
      if (!await _file!.exists()) {
        await _file!.create(recursive: true);
      }
      await info('log_init', {'path': _file!.path});
    } catch (_) {
      // If logging can't initialize, do NOT crash the app.
      _file = null;
    }
  }

  Future<void> info(String event, [Map<String, Object?> data = const {}]) async {
    await _write('info', event, data);
  }

  Future<void> warn(String event, [Map<String, Object?> data = const {}]) async {
    await _write('warn', event, data);
  }

  Future<void> error(String event, [Map<String, Object?> data = const {}]) async {
    await _write('error', event, data);
  }

  Future<void> _write(String level, String event, Map<String, Object?> data) async {
    try {
      if (!_init) await init();
      if (_file == null) return;
      final payload = <String, Object?>{
        'ts': DateTime.now().toUtc().toIso8601String(),
        'level': level,
        'event': event,
        'data': data,
      };
      await _file!.writeAsString('${jsonEncode(payload)}\n', mode: FileMode.append, flush: false);
    } catch (_) {
      // Nope.
    }
  }

  Future<List<String>> tail({int maxLines = 200}) async {
    try {
      if (!_init) await init();
      if (_file == null) return const [];
      final lines = await _file!.readAsLines();
      if (lines.length <= maxLines) return lines;
      return lines.sublist(lines.length - maxLines);
    } catch (_) {
      return const [];
    }
  }

  Future<void> clear() async {
    try {
      if (!_init) await init();
      if (_file == null) return;
      await _file!.writeAsString('');
      await info('log_cleared');
    } catch (_) {
      // shrug
    }
  }
}
