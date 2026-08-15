import 'dart:async';
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

  Future<File> _file({
    bool createDirectory = true,
    int? generation,
  }) async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}neura_therapy');
    final mayCreate =
        createDirectory && (generation == null || _isCurrent(generation));
    if (mayCreate && !await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}responses.jsonl');
  }

  Future<TherapyResponse> save({
    required TherapyPrompt prompt,
    required String text,
  }) {
    return _enqueueWrite((generation) async {
      final crypto = await _ensureCrypto();
      _requireCurrent(generation);
      final response = TherapyResponse(
        id: _id(),
        promptId: prompt.id,
        method: prompt.method,
        promptTitle: prompt.title,
        text: text,
        timestamp: DateTime.now(),
      );
      final encrypted = await crypto.encryptJson(response.toMap());
      _requireCurrent(generation);
      final f = await _file(generation: generation);
      _requireCurrent(generation);
      await f.writeAsString(
        '${jsonEncode({'blob': encrypted})}\n',
        mode: FileMode.append,
        flush: true,
      );
      await _removeStaleWrite(f, generation);
      return response;
    });
  }

  /// All saved responses, newest first. Corrupt/undecryptable lines are
  /// skipped rather than thrown, matching MemoryGraphService's behavior.
  Future<List<TherapyResponse>> all() async {
    if (_writesSuspended) return [];
    final generation = _dataGeneration;
    final crypto = await _ensureCrypto();
    if (!_isCurrent(generation)) return [];
    final f = await _file(createDirectory: false);
    if (!_isCurrent(generation) || !await f.exists()) return [];

    final lines = await f.readAsLines();
    if (!_isCurrent(generation)) return [];
    final out = <TherapyResponse>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final dec = await crypto.decryptJson(m['blob'] as String);
        if (!_isCurrent(generation)) return [];
        out.add(TherapyResponse.fromMap(dec));
      } catch (_) {
        // Skip corrupt lines.
      }
    }
    return _isCurrent(generation) ? out.reversed.toList() : [];
  }

  Future<List<TherapyResponse>> forPrompt(String promptId) async {
    final everything = await all();
    return everything.where((r) => r.promptId == promptId).toList();
  }

  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _dataGeneration += 1;
    Object? drainFailure;
    try {
      await _writeQueue.timeout(const Duration(seconds: 3));
    } catch (error) {
      drainFailure = error;
    }
    _crypto = null;
    _writeQueue = Future<void>.value();
    if (drainFailure != null) {
      throw StateError(
          'Therapy journal writer shutdown could not be verified.');
    }
  }

  Future<T> _enqueueWrite<T>(
    Future<T> Function(int generation) operation,
  ) {
    if (_writesSuspended) {
      return Future<T>.error(
        StateError('Therapy journal writes are suspended.'),
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
      throw StateError('Therapy journal operation was invalidated.');
    }
  }

  Future<void> _removeStaleWrite(File file, int generation) async {
    if (_isCurrent(generation)) return;
    if (await file.exists()) await file.delete();
    throw StateError('Therapy journal write was invalidated.');
  }
}
