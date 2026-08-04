import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../../core/memory/memory_crypto.dart';
import 'therapy_models.dart';

/// Local-first, encrypted-at-rest store for saved [TherapyResponse]s.
/// Mirrors [MemoryGraphService]'s JSONL-append design and reuses the same
/// per-install [MemoryCrypto] key - one local-data encryption key for the
/// app rather than a proliferation of near-identical per-feature ones.
class TherapyResponseStore {
  static final TherapyResponseStore I = TherapyResponseStore._();
  TherapyResponseStore._();

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

  Future<File> _file() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}neura_therapy');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}responses.jsonl');
  }

  Future<TherapyResponse> save({
    required TherapyPrompt prompt,
    required String text,
  }) async {
    final crypto = await _ensureCrypto();
    final response = TherapyResponse(
      id: _id(),
      promptId: prompt.id,
      method: prompt.method,
      promptTitle: prompt.title,
      text: text,
      timestamp: DateTime.now(),
    );
    final encrypted = await crypto.encryptJson(response.toMap());
    final f = await _file();
    await f.writeAsString('${jsonEncode({'blob': encrypted})}\n', mode: FileMode.append, flush: true);
    return response;
  }

  /// All saved responses, newest first. Corrupt/undecryptable lines are
  /// skipped rather than thrown, matching MemoryGraphService's behavior.
  Future<List<TherapyResponse>> all() async {
    final crypto = await _ensureCrypto();
    final f = await _file();
    if (!f.existsSync()) return [];

    final lines = await f.readAsLines();
    final out = <TherapyResponse>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final dec = await crypto.decryptJson(m['blob'] as String);
        out.add(TherapyResponse.fromMap(dec));
      } catch (_) {
        // Skip corrupt lines.
      }
    }
    return out.reversed.toList();
  }

  Future<List<TherapyResponse>> forPrompt(String promptId) async {
    final everything = await all();
    return everything.where((r) => r.promptId == promptId).toList();
  }
}
