import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_log_record.dart';

/// Bounded, structured, privacy-filtered application log for Neura.
///
/// Records are serialized through one queue so concurrent services cannot
/// corrupt the NDJSON file. Logging is deliberately best-effort: a storage
/// failure is never allowed to become an application failure.
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const int _maxBytes = 5 * 1024 * 1024;
  static const int _maxBackupFiles = 2;
  static const int _sizeCheckInterval = 100;
  static const int _maxTailLines = 5000;

  final AppLogRecordFactory _records = AppLogRecordFactory(
    platform: Platform.operatingSystem,
  );
  Future<void> _writeQueue = Future<void>.value();
  File? _file;
  bool _initialized = false;
  bool _suspendedForDataWipe = false;
  int _writesSinceSizeCheck = 0;

  Future<void> init() {
    return _enqueue(() async {
      final newlyInitialized = await _ensureInitialized();
      if (!newlyInitialized) return;
      await _appendRecord(
        'info',
        'log_init',
        <String, Object?>{'path': _file?.path ?? 'unavailable'},
      );
    });
  }

  /// Verifies that the log destination can be opened and written.
  ///
  /// Unlike normal best-effort logging, this method propagates failure so the
  /// global error pipeline can retain its dependency-free bootstrap sink.
  Future<void> initChecked() {
    return _enqueue(() async {
      final newlyInitialized = await _ensureInitialized();
      await _appendRecord(
        'info',
        newlyInitialized ? 'log_init' : 'log_healthcheck',
        <String, Object?>{'path': _file?.path ?? 'unavailable'},
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

  /// Error write used by the global pipeline. Failure is surfaced so that
  /// pipeline can fall back to its pre-plugin bootstrap log.
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
    if (_initialized && _file != null) return false;
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}logs',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}neura.log.ndjson',
    );
    await _migrateLegacyLog(support, file);
    _file = file;
    if (!await _file!.exists()) {
      await _file!.create(recursive: true);
    } else {
      await _rotateIfOversized();
    }
    _initialized = true;
    return true;
  }

  Future<void> _migrateLegacyLog(Directory support, File destination) async {
    if (await destination.exists()) return;
    final legacy = File(
      '${support.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}neura.log.ndjson',
    );
    try {
      if (await legacy.exists()) {
        await legacy.rename(destination.path);
      }
      final legacyBackup = File('${legacy.path}.old');
      if (await legacyBackup.exists()) {
        await legacyBackup.rename('${destination.path}.1');
      }
    } catch (_) {
      // A failed migration must not make logging unavailable. The new file is
      // created below, and the old copy remains untouched for manual recovery.
    }
  }

  Future<void> _appendRecord(
    String level,
    String event,
    Map<String, Object?> data,
  ) async {
    if (_suspendedForDataWipe) return;
    final file = _file;
    if (file == null) return;
    final record = _records.build(level: level, event: event, data: data);
    await file.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: level == 'error',
    );
    _writesSinceSizeCheck += 1;
    if (_writesSinceSizeCheck >= _sizeCheckInterval) {
      _writesSinceSizeCheck = 0;
      await _rotateIfOversized();
    }
  }

  Future<void> _rotateIfOversized() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    if (await file.length() <= _maxBytes) return;
    for (var index = _maxBackupFiles; index >= 1; index -= 1) {
      final source = index == 1
          ? file
          : File('${file.path}.${index - 1}');
      if (!await source.exists()) continue;
      final destination = File('${file.path}.$index');
      if (await destination.exists()) await destination.delete();
      await source.rename(destination.path);
    }
    _file = File(file.path);
    await _file!.create(recursive: true);
  }

  Future<List<String>> tail({int maxLines = 200}) async {
    if (_suspendedForDataWipe) return const <String>[];
    await init();
    await _writeQueue;
    try {
      final file = _file;
      if (file == null || !await file.exists()) return const <String>[];
      final lines = await file.readAsLines();
      final take = maxLines.clamp(1, _maxTailLines).toInt();
      if (lines.length <= take) return lines;
      return lines.sublist(lines.length - take);
    } catch (_) {
      return const <String>[];
    }
  }

  /// Creates a chronological copy containing rotated and current app logs.
  Future<String> exportCopy() async {
    if (_suspendedForDataWipe) {
      throw StateError('Application logging is suspended until restart.');
    }
    await init();
    await _writeQueue;
    final file = _file;
    if (file == null) throw StateError('Application log is unavailable.');

    final support = await getApplicationSupportDirectory();
    final exports = Directory(
      '${support.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}exports',
    );
    await exports.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final target = File(
      '${exports.path}${Platform.pathSeparator}'
      'neura-app-log-$stamp.ndjson',
    );
    final sink = target.openWrite();
    try {
      for (var index = _maxBackupFiles; index >= 1; index -= 1) {
        final backup = File('${file.path}.$index');
        if (await backup.exists()) await sink.addStream(backup.openRead());
      }
      if (await file.exists()) await sink.addStream(file.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
    return target.path;
  }

  Future<String?> getLogPath() async {
    if (_suspendedForDataWipe) return null;
    await init();
    await _writeQueue;
    return _file?.path;
  }

  Future<void> clear() {
    return _enqueue(() async {
      await _ensureInitialized();
      final file = _file;
      if (file == null) return;
      await file.writeAsString('', flush: true);
      for (var index = 1; index <= _maxBackupFiles; index += 1) {
        final backup = File('${file.path}.$index');
        if (await backup.exists()) await backup.delete();
      }
      await _appendRecord('info', 'log_cleared', const <String, Object?>{});
    });
  }

  /// Drains and suspends logging before the app-data tree is removed.
  /// Logging intentionally resumes only after a process restart.
  Future<void> resetAfterDataWipe() async {
    _suspendedForDataWipe = true;
    await _writeQueue;
    _file = null;
    _initialized = false;
    _writesSinceSizeCheck = 0;
  }
}
