import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'neura_error_redactor.dart';

/// Dependency-free, best-effort error log available before plugins start.
///
/// The regular AppLog uses path_provider, so it cannot safely be the first
/// destination for plugin/bootstrap failures. This file uses only dart:io and
/// rotates at a small fixed size. Once AppLog is ready, the error pipeline
/// hands new events to it instead.
class NeuraBootstrapLog {
  NeuraBootstrapLog._();

  static const int _maxBytes = 512 * 1024;
  static Future<void> _writes = Future<void>.value();
  static bool _suspendedForDataWipe = false;

  static String get location => _file.path;

  static String get displayLocation {
    if (Platform.isWindows) {
      return r'%LOCALAPPDATA%\Neura OS\Logs\bootstrap_crash.ndjson';
    }
    if (Platform.isMacOS) {
      return '~/Library/Logs/Neura OS/bootstrap_crash.ndjson';
    }
    if (Platform.isLinux &&
        (Platform.environment['XDG_STATE_HOME']?.trim().isNotEmpty ?? false)) {
      return r'$XDG_STATE_HOME/neura_os/bootstrap_crash.ndjson';
    }
    if (Platform.isLinux) {
      return '~/.local/state/neura_os/bootstrap_crash.ndjson';
    }
    return r'$TMPDIR/neura_os/bootstrap_crash.ndjson';
  }

  static File get _file {
    late final Directory root;
    final environment = Platform.environment;

    if (Platform.isWindows &&
        (environment['LOCALAPPDATA']?.trim().isNotEmpty ?? false)) {
      root = Directory('${environment['LOCALAPPDATA']}\\Neura OS\\Logs');
    } else if (Platform.isMacOS &&
        (environment['HOME']?.trim().isNotEmpty ?? false)) {
      root = Directory('${environment['HOME']}/Library/Logs/Neura OS');
    } else if (Platform.isLinux &&
        (environment['XDG_STATE_HOME']?.trim().isNotEmpty ?? false)) {
      root = Directory('${environment['XDG_STATE_HOME']}/neura_os');
    } else if (Platform.isLinux &&
        (environment['HOME']?.trim().isNotEmpty ?? false)) {
      root = Directory('${environment['HOME']}/.local/state/neura_os');
    } else {
      // Android/iOS and restricted desktop environments still expose a
      // writable system-temp directory without requiring a Flutter plugin.
      root = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}neura_os',
      );
    }

    return File(
      '${root.path}${Platform.pathSeparator}bootstrap_crash.ndjson',
    );
  }

  static Future<void> append(Map<String, Object?> payload) {
    if (_suspendedForDataWipe) return Future<void>.value();
    final operation = _writes.then((_) => _append(payload));
    // A logging failure must never become another unhandled application error.
    _writes = operation.catchError((_) {});
    return operation.catchError((_) {});
  }

  static Future<void> drain() => _writes;

  /// Returns a bounded, privacy-filtered tail suitable for Diagnostics UI.
  /// Unknown keys are deliberately dropped.
  static Future<List<Map<String, Object?>>> tail({int maxRecords = 100}) async {
    if (_suspendedForDataWipe || maxRecords <= 0) return const [];
    await _writes;
    try {
      final file = _file;
      final lines = <String>[];
      final previous = File('${file.path}.old');
      if (await previous.exists()) lines.addAll(await previous.readAsLines());
      if (await file.exists()) lines.addAll(await file.readAsLines());
      if (lines.isEmpty) return const [];
      final start = lines.length > maxRecords ? lines.length - maxRecords : 0;
      final records = <Map<String, Object?>>[];
      for (final line in lines.skip(start)) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) continue;
          records.add(_sanitizeStoredRecord(decoded));
        } catch (_) {
          // A partial final line must not make the remaining log unreadable.
        }
      }
      return List<Map<String, Object?>>.unmodifiable(records);
    } catch (_) {
      return const [];
    }
  }

  /// Deletes the live and rotated early logs for a manual diagnostics clear.
  /// Full data wipe must use [suspendForDataWipe] to prevent recreation.
  static Future<void> clear() {
    final operation = _writes.then((_) => _deleteFiles());
    _writes = operation.catchError((_) {});
    return operation.catchError((_) {});
  }

  /// Synchronously blocks future writes, drains queued writes, then removes
  /// both files. A clean process restart is the only resume boundary.
  static Future<void> suspendForDataWipe() {
    _suspendedForDataWipe = true;
    final operation = _writes.then((_) => _deleteFiles());
    _writes = operation.catchError((_) {});
    return operation;
  }

  /// Writes a sanitized copy for support export and returns its path.
  /// Returns null if no records are available or the copy cannot be written.
  static Future<String?> exportCopy({String? destinationPath}) async {
    try {
      final records = await tail(maxRecords: 10000);
      if (records.isEmpty) return null;
      final stamp =
          DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      final exportFile = destinationPath == null
          ? File(
              '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'neura_bootstrap_export_$stamp.ndjson',
            )
          : File(destinationPath);
      await exportFile.parent.create(recursive: true);
      final content = records.map(jsonEncode).join('\n');
      await exportFile.writeAsString('$content\n', flush: true);
      return exportFile.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _append(Map<String, Object?> payload) async {
    if (_suspendedForDataWipe) return;
    final file = _file;
    await file.parent.create(recursive: true);
    if (await file.exists() && await file.length() >= _maxBytes) {
      final previous = File('${file.path}.old');
      if (await previous.exists()) await previous.delete();
      await file.rename(previous.path);
    }

    final record = _sanitizeStoredRecord(<String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...payload,
    });
    await file.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Map<String, Object?> _sanitizeStoredRecord(Map<dynamic, dynamic> raw) {
    String field(String key) =>
        NeuraErrorRedactor.message(raw[key]?.toString() ?? '');
    final errorType = NeuraErrorRedactor.tag(
      raw['error_type']?.toString() ?? '',
      fallback: 'UnknownError',
    );

    return <String, Object?>{
      'timestamp': field('timestamp'),
      'source': NeuraErrorRedactor.tag(raw['source']?.toString() ?? ''),
      'error_type': errorType,
      'message': 'An unexpected $errorType was contained.',
      'stack': NeuraErrorRedactor.stack(raw['stack']?.toString() ?? ''),
      'fatal': raw['fatal'] == true,
      'phase': NeuraErrorRedactor.tag(raw['phase']?.toString() ?? ''),
    };
  }

  static Future<void> _deleteFiles() async {
    final failures = <Object>[];
    for (final file in [_file, File('${_file.path}.old')]) {
      try {
        if (await file.exists()) await file.delete();
        if (await file.exists()) {
          failures.add(StateError('A bootstrap log remained after deletion.'));
        }
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw StateError(
        'Could not delete every bootstrap diagnostic log '
        '(${failures.length} failure(s)).',
      );
    }
  }
}
