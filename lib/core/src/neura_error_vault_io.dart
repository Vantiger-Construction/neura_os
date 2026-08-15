import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../modules/core/app_log_record.dart';
import '../neura_fault_event.dart';

/// Crash-safe local vault.
/// Stores JSONL entries in system temp so we never depend on extra plugins.
/// This is *not* meant for long-term storage; it's a debugging and post-mortem breadcrumb trail.
class NeuraErrorVault {
  static const _fileName = 'neura_error_vault.jsonl';
  static const _maxBytes = 1024 * 512; // 512 KB
  static const _maxBackupFiles = 3;
  static bool _suspendedForDataWipe = false;
  static Future<void> _writeQueue = Future<void>.value();

  static File _file() => File('${Directory.systemTemp.path}${Platform.pathSeparator}$_fileName');

  static Future<void> append(NeuraFaultEvent event) {
    if (_suspendedForDataWipe) return Future<void>.value();
    final next = _writeQueue.then((_) => _appendNow(event));
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static Future<void> _appendNow(NeuraFaultEvent event) async {
    try {
      final f = _file();
      await _rotateIfNeeded(f);
      final line = jsonEncode(
        AppLogSanitizer.map(
          Map<String, Object?>.from(event.toJson()),
        ),
      );
      await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // last line of defense: never crash while trying to log a crash
    }
  }

  static Future<String?> getVaultPath() async {
    try {
      return _file().path;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> tail({int maxLines = 200}) async {
    try {
      await _writeQueue;
      final f = _file();
      final lines = <String>[];
      for (var index = _maxBackupFiles; index >= 1; index -= 1) {
        final backup = File('${f.path}.$index');
        if (await backup.exists()) lines.addAll(await backup.readAsLines());
      }
      if (await f.exists()) lines.addAll(await f.readAsLines());
      final take = maxLines.clamp(1, 10000).toInt();
      final selected = lines.length <= take
          ? lines
          : lines.sublist(lines.length - take);
      return selected.map(_sanitizePersistedLine).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> clear() async {
    await _writeQueue;
    await _deleteFiles();
  }

  static Future<String> exportCopy() async {
    await _writeQueue;
    final lines = await tail(maxLines: 10000);
    if (lines.isEmpty) throw StateError('The crash vault is empty.');
    final support = await getApplicationSupportDirectory();
    final exports = Directory(
      '${support.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}exports',
    );
    await exports.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final target = File(
      '${exports.path}${Platform.pathSeparator}'
      'neura-crash-vault-$stamp.jsonl',
    );
    await target.writeAsString('${lines.join('\n')}\n', flush: true);
    return target.path;
  }

  static Future<void> suspendForDataWipe() async {
    _suspendedForDataWipe = true;
    await _writeQueue;
    await _deleteFiles();
  }

  static String _sanitizePersistedLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return '{"type":"corrupt_record"}';
      return jsonEncode(
        AppLogSanitizer.map(Map<String, Object?>.from(decoded)),
      );
    } catch (_) {
      return '{"type":"corrupt_record"}';
    }
  }

  static Future<void> _deleteFiles() async {
    final f = _file();
    if (await f.exists()) await f.delete();
    for (var index = 1; index <= _maxBackupFiles; index += 1) {
      final backup = File('${f.path}.$index');
      if (await backup.exists()) await backup.delete();
    }
  }

  static Future<void> _rotateIfNeeded(File f) async {
    try {
      if (!await f.exists()) return;
      final len = await f.length();
      if (len < _maxBytes) return;

      // Rotate: vault -> vault.1 -> vault.2 ...
      for (int i = _maxBackupFiles - 1; i >= 1; i--) {
        final src = File('${f.path}.$i');
        final dst = File('${f.path}.${i + 1}');
        if (await src.exists()) {
          if (await dst.exists()) await dst.delete();
          await src.rename(dst.path);
        }
      }

      final first = File('${f.path}.1');
      if (await first.exists()) await first.delete();
      await f.rename(first.path);
    } catch (_) {
      // ignore
    }
  }
}
