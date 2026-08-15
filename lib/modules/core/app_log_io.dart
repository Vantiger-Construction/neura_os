import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny persistent log for Neura OS.
///
/// Stores newline-delimited JSON (NDJSON) so one bad line doesn't brick the whole log.
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  // Without a cap this file grows forever across every launch in the app's
  // history (observed 1.4GB+ in the wild). Rotate to a single `.old` backup
  // once the live file crosses this size.
  static const int _maxBytes = 10 * 1024 * 1024;
  static const int _sizeCheckInterval = 500;

  File? _file;
  bool _init = false;
  int _writesSinceSizeCheck = 0;
  int _activeWrites = 0;
  Completer<void>? _writesDrained;
  bool _suspendedForDataWipe = false;

  Future<void> init() async {
    if (_suspendedForDataWipe) return;
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
      } else {
        await _rotateIfOversized();
      }
      await info('log_init', {'path': _file!.path});
    } catch (_) {
      // If logging can't initialize, do NOT crash the app.
      _file = null;
    }
  }

  Future<void> _rotateIfOversized() async {
    final file = _file;
    if (file == null) return;
    try {
      if (await file.length() <= _maxBytes) return;
      final path = file.path;
      final old = File('$path.old');
      if (await old.exists()) {
        await old.delete();
      }
      await file.rename(old.path);
      _file = File(path)..createSync(recursive: true);
    } catch (_) {
      // Best effort -- keep appending to the existing file rather than lose logging.
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
    if (_suspendedForDataWipe) return;
    _activeWrites += 1;
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
      if (++_writesSinceSizeCheck >= _sizeCheckInterval) {
        _writesSinceSizeCheck = 0;
        await _rotateIfOversized();
      }
    } catch (_) {
      // Nope.
    } finally {
      _activeWrites -= 1;
      if (_activeWrites == 0) {
        final drained = _writesDrained;
        _writesDrained = null;
        if (drained != null && !drained.isCompleted) drained.complete();
      }
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

  /// Drains and suspends logging, then releases the old path before its
  /// containing app-data directory is removed. A restart resumes logging.
  Future<void> resetAfterDataWipe() async {
    _suspendedForDataWipe = true;
    if (_activeWrites > 0) {
      final drained = _writesDrained ??= Completer<void>();
      await drained.future;
    }
    _file = null;
    _init = false;
    _writesSinceSizeCheck = 0;
  }
}
