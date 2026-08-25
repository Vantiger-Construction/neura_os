import 'dart:async';
import 'dart:convert';

import '../../startup/neura_prefs_cache.dart';
import 'app_log_record.dart';

/// Web-safe structured logger backed by a bounded SharedPreferences tail.
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const String _key = 'neura_log_ndjson';
  static const int _maxStoredLines = 500;
  static const int _maxTailLines = 500;

  final AppLogRecordFactory _records = AppLogRecordFactory(platform: 'web');
  Future<void> _writeQueue = Future<void>.value();
  bool _initialized = false;
  bool _suspendedForDataWipe = false;

  Future<void> init() {
    return _enqueue(() async {
      final newlyInitialized = await _ensureInitialized();
      if (!newlyInitialized) return;
      await _appendRecord(
        'info',
        'log_init',
        const <String, Object?>{'storage': 'browser_preferences'},
      );
    });
  }

  Future<void> initChecked() {
    return _enqueue(() async {
      final newlyInitialized = await _ensureInitialized();
      await _appendRecord(
        'info',
        newlyInitialized ? 'log_init' : 'log_healthcheck',
        const <String, Object?>{'storage': 'browser_preferences'},
      );
    }, propagateErrors: true);
  }

  Future<void> info(
    String event, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    return _write('info', event, data);
  }

  Future<void> warn(
    String event, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    return _write('warn', event, data);
  }

  Future<void> error(
    String event, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    return _write('error', event, data);
  }

  Future<void> errorChecked(
    String event, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    return _write('error', event, data, propagateErrors: true);
  }

  Future<void> exception(
    String event,
    Object error,
    StackTrace stack, {
    Map<String, Object?> context = const <String, Object?>{},
    String? safeMessage,
  }) {
    final errorType = error.runtimeType.toString();
    return _write('error', event, <String, Object?>{
      ...context,
      'error_type': errorType,
      'message': safeMessage ?? '$errorType details withheld',
      'stack': stack.toString(),
    });
  }

  Future<void> caught(
    String event,
    Object error,
    StackTrace stack, {
    Map<String, Object?> context = const <String, Object?>{},
    String? safeMessage,
  }) {
    final errorType = error.runtimeType.toString();
    return _write('warn', event, <String, Object?>{
      ...context,
      'handled': true,
      'error_type': errorType,
      'message': safeMessage ?? '$errorType details withheld',
      'stack': stack.toString(),
    });
  }

  Future<void> _write(
    String level,
    String event,
    Map<String, Object?> data, {
    bool propagateErrors = false,
  }) {
    return _enqueue(() async {
      await _ensureInitialized();
      await _appendRecord(level, event, data);
    }, propagateErrors: propagateErrors);
  }

  Future<void> _enqueue(
    Future<void> Function() operation, {
    bool propagateErrors = false,
  }) {
    if (_suspendedForDataWipe) return Future<void>.value();
    final next = _writeQueue.then<void>((_) async {
      if (_suspendedForDataWipe) return;
      await operation();
    });
    _writeQueue = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return propagateErrors ? next : _writeQueue;
  }

  Future<bool> _ensureInitialized() async {
    if (_suspendedForDataWipe) return false;
    if (_initialized) return false;
    // Access is intentionally the readiness check. If preferences are not yet
    // available, the queued operation is swallowed and a later write retries.
    NeuraPrefsCache.prefs;
    _initialized = true;
    return true;
  }

  Future<void> _appendRecord(
    String level,
    String event,
    Map<String, Object?> data,
  ) async {
    if (_suspendedForDataWipe) return;
    final prefs = NeuraPrefsCache.prefs;
    final current = prefs.getString(_key) ?? '';
    final record = _records.build(level: level, event: event, data: data);
    final lines = <String>[
      ...const LineSplitter().convert(current),
      jsonEncode(record),
    ];
    final trimmed = lines.length <= _maxStoredLines
        ? lines
        : lines.sublist(lines.length - _maxStoredLines);
    final stored = await prefs.setString(_key, '${trimmed.join('\n')}\n');
    if (!stored) throw StateError('Browser log write was not persisted.');
  }

  Future<List<String>> tail({int maxLines = 200}) async {
    if (_suspendedForDataWipe) return const <String>[];
    await init();
    await _writeQueue;
    try {
      final current = NeuraPrefsCache.prefs.getString(_key) ?? '';
      if (current.trim().isEmpty) return const <String>[];
      final lines = const LineSplitter().convert(current.trimRight());
      final take = maxLines.clamp(1, _maxTailLines).toInt();
      if (lines.length <= take) return lines;
      return lines.sublist(lines.length - take);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<String> exportCopy() {
    throw UnsupportedError(
      'Filesystem log export is unavailable in the browser build.',
    );
  }

  Future<String?> getLogPath() async => null;

  Future<void> clear() {
    return _enqueue(() async {
      await _ensureInitialized();
      await NeuraPrefsCache.prefs.remove(_key);
      await _appendRecord('info', 'log_cleared', const <String, Object?>{});
    });
  }

  Future<void> resetAfterDataWipe() async {
    _suspendedForDataWipe = true;
    await _writeQueue;
    try {
      await NeuraPrefsCache.prefs.remove(_key);
    } catch (_) {}
    _initialized = false;
  }
}
