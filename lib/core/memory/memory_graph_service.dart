import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'memory_crypto.dart';

/// Local-first encrypted memory graph.
///
/// - Encrypted at rest (AES-GCM via [MemoryCrypto])
/// - No database/codegen required (JSONL append-only)
/// - Crash-safe: corrupt lines are skipped
class MemoryGraphService {
  static final MemoryGraphService I = MemoryGraphService._();
  MemoryGraphService._();

  MemoryCrypto? _crypto;

  Future<MemoryCrypto> _ensureCrypto() async {
    _crypto ??= await MemoryCrypto.demo();
    return _crypto!;
  }

  String _id() {
    final r = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<Directory> _dir() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}neura_memory');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _nodesFile() async {
    final dir = await _dir();
    return File('${dir.path}${Platform.pathSeparator}nodes.jsonl');
  }

  Future<File> _edgesFile() async {
    final dir = await _dir();
    return File('${dir.path}${Platform.pathSeparator}edges.jsonl');
  }

  Future<String> logUserAction({
    required String kind,
    required Map<String, dynamic> payload,
    String? outcome,
  }) async {
    final crypto = await _ensureCrypto();
    final id = _id();
    final encrypted = await crypto.encryptJson(payload);
    final node = {
      'id': id,
      'type': 'ACTION:$kind',
      'ts': DateTime.now().toIso8601String(),
      'encryptedPayload': encrypted,
      'outcome': outcome,
    };
    final f = await _nodesFile();
    await f.writeAsString('${jsonEncode(node)}\n', mode: FileMode.append, flush: true);
    return id;
  }

  Future<String> logSuggestion({
    required String kind,
    required Map<String, dynamic> payload,
    String? userResponse,
    String? outcome,
  }) async {
    final crypto = await _ensureCrypto();
    final id = _id();
    final encrypted = await crypto.encryptJson({
      ...payload,
      if (userResponse != null) 'response': userResponse,
    });
    final node = {
      'id': id,
      'type': 'SUGGESTION:$kind',
      'ts': DateTime.now().toIso8601String(),
      'encryptedPayload': encrypted,
      'outcome': outcome,
    };
    final f = await _nodesFile();
    await f.writeAsString('${jsonEncode(node)}\n', mode: FileMode.append, flush: true);
    return id;
  }

  Future<void> link({required String src, required String dst, required String rel}) async {
    final edge = {
      'id': _id(),
      'src': src,
      'dst': dst,
      'rel': rel,
      'ts': DateTime.now().toIso8601String(),
    };
    final f = await _edgesFile();
    await f.writeAsString('${jsonEncode(edge)}\n', mode: FileMode.append, flush: true);
  }

  Future<List<Map<String, dynamic>>> recentNodes({int limit = 25}) async {
    final crypto = await _ensureCrypto();
    final f = await _nodesFile();
    if (!f.existsSync()) return [];

    final lines = await f.readAsLines();
    final tail = lines.length <= limit ? lines : lines.sublist(lines.length - limit);
    final out = <Map<String, dynamic>>[];

    for (final line in tail) {
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final dec = await crypto.decryptJson(m['encryptedPayload'] as String);
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
    return out.reversed.toList();
  }

  Future<void> resetAll() async {
    final nf = await _nodesFile();
    final ef = await _edgesFile();
    if (nf.existsSync()) await nf.delete();
    if (ef.existsSync()) await ef.delete();
  }

  Future<String> exportJson({int limit = 1000}) async {
    final nodes = await recentNodes(limit: limit);
    return jsonEncode({'nodes': nodes});
  }
}
