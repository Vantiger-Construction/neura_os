import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'memory_crypto.dart';
import 'bounded_stream_tail.dart';

/// Local-first encrypted memory graph.
///
/// - Encrypted at rest (AES-GCM via [MemoryCrypto])
/// - No database/codegen required (JSONL append-only)
/// - Crash-safe: corrupt lines are skipped
class MemoryGraphService {
  static final MemoryGraphService I = MemoryGraphService._();
  MemoryGraphService._();

  MemoryCrypto? _crypto;
  Future<void> _writeQueue = Future<void>.value();
  bool _writesSuspended = false;
  int _dataGeneration = 0;

  Future<MemoryCrypto> _ensureCrypto() async {
    _crypto ??= await MemoryCrypto.demo();
    return _crypto!;
  }

  String _id() {
    final r = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<Directory> _dir({bool create = true, int? generation}) async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}neura_memory');
    final mayCreate = create && (generation == null || _isCurrent(generation));
    if (mayCreate && !await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _nodesFile({
    bool createDirectory = true,
    int? generation,
  }) async {
    final dir = await _dir(
      create: createDirectory,
      generation: generation,
    );
    return File('${dir.path}${Platform.pathSeparator}nodes.jsonl');
  }

  Future<File> _edgesFile({
    bool createDirectory = true,
    int? generation,
  }) async {
    final dir = await _dir(
      create: createDirectory,
      generation: generation,
    );
    return File('${dir.path}${Platform.pathSeparator}edges.jsonl');
  }

  Future<String> logUserAction({
    required String kind,
    required Map<String, dynamic> payload,
    String? outcome,
  }) {
    return _enqueueWrite((generation) async {
      final crypto = await _ensureCrypto();
      _requireCurrent(generation);
      final id = _id();
      final encrypted = await crypto.encryptJson(payload);
      _requireCurrent(generation);
      final node = {
        'id': id,
        'type': 'ACTION:$kind',
        'ts': DateTime.now().toIso8601String(),
        'encryptedPayload': encrypted,
        'outcome': outcome,
      };
      final f = await _nodesFile(generation: generation);
      _requireCurrent(generation);
      await f.writeAsString(
        '${jsonEncode(node)}\n',
        mode: FileMode.append,
        flush: true,
      );
      await _removeStaleWrite(generation);
      return id;
    });
  }

  Future<String> logSuggestion({
    required String kind,
    required Map<String, dynamic> payload,
    String? userResponse,
    String? outcome,
  }) {
    return _enqueueWrite((generation) async {
      final crypto = await _ensureCrypto();
      _requireCurrent(generation);
      final id = _id();
      final encrypted = await crypto.encryptJson({
        ...payload,
        if (userResponse != null) 'response': userResponse,
      });
      _requireCurrent(generation);
      final node = {
        'id': id,
        'type': 'SUGGESTION:$kind',
        'ts': DateTime.now().toIso8601String(),
        'encryptedPayload': encrypted,
        'outcome': outcome,
      };
      final f = await _nodesFile(generation: generation);
      _requireCurrent(generation);
      await f.writeAsString(
        '${jsonEncode(node)}\n',
        mode: FileMode.append,
        flush: true,
      );
      await _removeStaleWrite(generation);
      return id;
    });
  }

  Future<void> link({
    required String src,
    required String dst,
    required String rel,
  }) {
    return _enqueueWrite((generation) async {
      final edge = {
        'id': _id(),
        'src': src,
        'dst': dst,
        'rel': rel,
        'ts': DateTime.now().toIso8601String(),
      };
      final f = await _edgesFile(generation: generation);
      _requireCurrent(generation);
      await f.writeAsString(
        '${jsonEncode(edge)}\n',
        mode: FileMode.append,
        flush: true,
      );
      await _removeStaleWrite(generation);
    });
  }

  Future<List<Map<String, dynamic>>> recentNodes({int limit = 25}) async {
    if (_writesSuspended || limit <= 0) return [];
    final generation = _dataGeneration;
    final crypto = await _ensureCrypto();
    if (!_isCurrent(generation)) return [];
    final f = await _nodesFile(createDirectory: false);
    if (!_isCurrent(generation) || !await f.exists()) return [];

    final tail = await boundedStreamTail(
      f.openRead().transform(utf8.decoder).transform(const LineSplitter()),
      limit: limit,
      isCurrent: () => _isCurrent(generation),
    );
    if (!_isCurrent(generation)) return [];
    final out = <Map<String, dynamic>>[];

    for (final line in tail) {
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final dec = await crypto.decryptJson(m['encryptedPayload'] as String);
        if (!_isCurrent(generation)) return [];
        out.add({
          'id': m['id'],
          'type': m['type'],
          'ts': m['ts'],
          'outcome': m['outcome'],
          'payload': dec,
        });
      } catch (_) {
        // Skip corrupt lines.
      }
    }

    // newest-first
    return _isCurrent(generation) ? out.reversed.toList() : [];
  }

  /// Nodes older than [cutoff], most-recent-of-the-matched-set first is NOT
  /// guaranteed -- returned in original (chronological, oldest-first) file
  /// order, capped to the last [limit] matches before [cutoff] so a long
  /// history doesn't mean decrypting the entire file. Read-only; unlike
  /// [recentNodes] (tail-of-file, always-recent), this is what
  /// long-range features (memory consolidation, recap export) should use.
  Future<List<Map<String, dynamic>>> nodesOlderThan(
    DateTime cutoff, {
    int limit = 200,
  }) async {
    if (_writesSuspended || limit <= 0) return [];
    final generation = _dataGeneration;
    final crypto = await _ensureCrypto();
    if (!_isCurrent(generation)) return [];
    final f = await _nodesFile(createDirectory: false);
    if (!_isCurrent(generation) || !await f.exists()) return [];

    final tail = await boundedStreamTail(
      f.openRead().transform(utf8.decoder).transform(const LineSplitter()),
      limit: limit,
      isCurrent: () => _isCurrent(generation),
      matches: (line) {
        if (line.trim().isEmpty) return false;
        try {
          final m = jsonDecode(line) as Map<String, dynamic>;
          final ts = DateTime.tryParse(m['ts'] as String? ?? '');
          return !(ts == null || !ts.isBefore(cutoff));
        } catch (_) {
          // Skip corrupt lines.
          return false;
        }
      },
    );
    if (!_isCurrent(generation)) return [];

    final out = <Map<String, dynamic>>[];
    for (final line in tail) {
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final dec = await crypto.decryptJson(m['encryptedPayload'] as String);
        if (!_isCurrent(generation)) return [];
        out.add({
          'id': m['id'],
          'type': m['type'],
          'ts': m['ts'],
          'outcome': m['outcome'],
          'payload': dec,
        });
      } catch (_) {
        // Skip corrupt lines.
      }
    }
    return _isCurrent(generation) ? out : [];
  }

  /// Nodes with `ts` inside `[start, end)`, chronological (oldest-first)
  /// order, capped to the last [limit] matches -- same O(n) ts-only scan
  /// before decrypting as [nodesOlderThan]. For recap-style features that
  /// need a bounded date window rather than "everything before a cutoff".
  Future<List<Map<String, dynamic>>> nodesBetween(
    DateTime start,
    DateTime end, {
    int limit = 500,
  }) async {
    if (_writesSuspended || limit <= 0) return [];
    final generation = _dataGeneration;
    final crypto = await _ensureCrypto();
    if (!_isCurrent(generation)) return [];
    final f = await _nodesFile(createDirectory: false);
    if (!_isCurrent(generation) || !await f.exists()) return [];

    final tail = await boundedStreamTail(
      f.openRead().transform(utf8.decoder).transform(const LineSplitter()),
      limit: limit,
      isCurrent: () => _isCurrent(generation),
      matches: (line) {
        if (line.trim().isEmpty) return false;
        try {
          final m = jsonDecode(line) as Map<String, dynamic>;
          final ts = DateTime.tryParse(m['ts'] as String? ?? '');
          return !(ts == null || ts.isBefore(start) || !ts.isBefore(end));
        } catch (_) {
          // Skip corrupt lines.
          return false;
        }
      },
    );
    if (!_isCurrent(generation)) return [];

    final out = <Map<String, dynamic>>[];
    for (final line in tail) {
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final dec = await crypto.decryptJson(m['encryptedPayload'] as String);
        if (!_isCurrent(generation)) return [];
        out.add({
          'id': m['id'],
          'type': m['type'],
          'ts': m['ts'],
          'outcome': m['outcome'],
          'payload': dec,
        });
      } catch (_) {
        // Skip corrupt lines.
      }
    }
    return _isCurrent(generation) ? out : [];
  }

  Future<void> resetAll() => _enqueueWrite((_) => _purgeGraphDirectory());

  /// Suspends and drains graph writes before the device key and graph files
  /// are removed. A restart is the only resume boundary.
  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _dataGeneration += 1;
    final drain = _writeQueue;
    try {
      await drain.timeout(const Duration(seconds: 3));
      await _purgeGraphDirectory();
    } catch (_) {
      unawaited(
        drain
            .then<void>(
              (_) => _purgeGraphDirectory(),
              onError: (_, __) => _purgeGraphDirectory(),
            )
            .catchError((_) {}),
      );
      rethrow;
    } finally {
      _crypto = null;
      _writeQueue = Future<void>.value();
    }
  }

  Future<String> exportJson({int limit = 1000}) async {
    final nodes = await recentNodes(limit: limit);
    return jsonEncode({'nodes': nodes});
  }

  Future<T> _enqueueWrite<T>(
    Future<T> Function(int generation) operation,
  ) {
    if (_writesSuspended) {
      return Future<T>.error(
        StateError('Memory graph writes are suspended.'),
      );
    }
    final generation = _dataGeneration;
    Future<T> run() {
      _requireCurrent(generation);
      return operation(generation);
    }

    final next = _writeQueue.then<T>(
      (_) => run(),
      onError: (_) => run(),
    );
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  bool _isCurrent(int generation) =>
      !_writesSuspended && generation == _dataGeneration;

  void _requireCurrent(int generation) {
    if (!_isCurrent(generation)) {
      throw StateError('Memory graph operation was invalidated.');
    }
  }

  Future<void> _removeStaleWrite(int generation) async {
    if (_isCurrent(generation)) return;
    await _purgeGraphDirectory();
    throw StateError('Memory graph write was invalidated.');
  }

  Future<void> _purgeGraphDirectory() async {
    final directory = await _dir(create: false);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
