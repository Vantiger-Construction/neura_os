import 'dart:convert';
import 'dart:io';

import '../neura_fault_event.dart';

/// Crash-safe local vault.
/// Stores JSONL entries in system temp so we never depend on extra plugins.
/// This is *not* meant for long-term storage; it's a debugging and post-mortem breadcrumb trail.
class NeuraErrorVault {
  static const _fileName = 'neura_error_vault.jsonl';
  static const _maxBytes = 1024 * 512; // 512 KB
  static const _maxBackupFiles = 3;

  static File _file() => File('${Directory.systemTemp.path}${Platform.pathSeparator}$_fileName');

  static Future<void> append(NeuraFaultEvent event) async {
    try {
      final f = _file();
      await _rotateIfNeeded(f);
      final line = jsonEncode(event.toJson());
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
