import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/core/memory/memory_graph_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_path_provider.dart';

class _CountingAesGcm extends DartAesGcm {
  _CountingAesGcm({required super.secretKeyLength, required super.nonceLength});

  int decryptions = 0;

  @override
  List<int> decryptSync(
    SecretBox secretBox, {
    required SecretKeyData secretKeyData,
    List<int> aad = const <int>[],
  }) {
    decryptions++;
    return super.decryptSync(secretBox, secretKeyData: secretKeyData, aad: aad);
  }
}

class _QueryCryptography extends DartCryptography {
  late _CountingAesGcm cipher;

  @override
  AesGcm aesGcm({int secretKeyLength = 32, int nonceLength = 12}) =>
      cipher = _CountingAesGcm(
        secretKeyLength: secretKeyLength,
        nonceLength: nonceLength,
      );
}

class _PausedNodesFile extends Fake implements File {
  _PausedNodesFile(this.delegate, this.bytes);

  final File delegate;
  final Stream<List<int>> bytes;

  @override
  Future<bool> exists() => delegate.exists();

  @override
  Stream<List<int>> openRead([int? start, int? end]) => bytes;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final secureValues = <String, String>{};
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('neura-memory-query-test-');
    registerMockPathProvider(rootPath: root.path);
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secureChannel, (
      call,
    ) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return secureValues[key];
        case 'write':
          secureValues[key] = args['value'] as String;
          return null;
        case 'delete':
          secureValues.remove(key);
          return null;
      }
      throw StateError('Unexpected secure storage operation: ${call.method}');
    });
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      null,
    );
    if (await root.exists()) await root.delete(recursive: true);
  });

  // The graph intentionally stays suspended until process restart after a
  // wipe, so exercise this lifecycle in one test without adding a reset seam.
  test(
    'bounded encrypted graph queries discard in-flight results on wipe',
    () async {
      final previousCryptography = Cryptography.instance;
      final countingCryptography = _QueryCryptography();
      Cryptography.instance = countingCryptography;
      addTearDown(() => Cryptography.instance = previousCryptography);
      final graph = MemoryGraphService.I;
      final crypto = await MemoryCrypto.demo();
      final cipher = countingCryptography.cipher;
      final start = DateTime.utc(2026, 1, 2);
      final end = DateTime.utc(2026, 1, 4);
      const privateText = 'synthetic private query fixture 🐾';
      await graph.logUserAction(
        kind: 'fixture',
        payload: {'text': privateText},
      );
      final nodes = File(
        '${root.path}${Platform.pathSeparator}neura_memory'
        '${Platform.pathSeparator}nodes.jsonl',
      );
      expect(await nodes.readAsString(), isNot(contains(privateText)));

      Future<String> record(String id, DateTime ts) async => jsonEncode({
            'id': id,
            'type': 'ACTION:fixture',
            'ts': ts.toIso8601String(),
            'encryptedPayload': await crypto.encryptJson({
              'id': id,
              'text': privateText,
            }),
          });
      final history = [
        await record('a', start.subtract(const Duration(days: 1))),
        await record('b', start),
        'broken json',
        '',
        jsonEncode({'ts': 'invalid timestamp'}),
        await record('c', start.add(const Duration(days: 1))),
        jsonEncode({
          'ts': start.add(const Duration(days: 1)).toIso8601String(),
          'encryptedPayload': 'broken ciphertext',
        }),
        await record('d', end),
        '',
        'broken final line',
      ].join('\n');
      await nodes.writeAsString('$history\n');

      // recentNodes bounds physical lines before corrupt/blank lines are skipped.
      expect(await graph.recentNodes(limit: 2), isEmpty);
      expect(cipher.decryptions, 0);
      final recent = await graph.recentNodes(limit: 4);
      expect(recent.map((node) => node['id']), ['d']);
      expect(recent.single['payload'], {'id': 'd', 'text': privateText});
      expect(cipher.decryptions, 1);
      cipher.decryptions = 0;
      final older = await graph.nodesOlderThan(end, limit: 2);
      expect(older.map((node) => node['id']), ['c']);
      expect(cipher.decryptions, 1);
      cipher.decryptions = 0;
      final between = await graph.nodesBetween(start, end, limit: 3);
      expect(between.map((node) => node['id']), ['b', 'c']);
      expect(between.map((node) => node['payload']), [
        {'id': 'b', 'text': privateText},
        {'id': 'c', 'text': privateText},
      ]);
      expect(cipher.decryptions, 2);
      cipher.decryptions = 0;
      // A corrupt selected record consumes its slot; never backfill or decrypt
      // an older record outside the selected tail to meet the requested limit.
      expect(await graph.nodesBetween(start, end, limit: 1), isEmpty);
      expect(cipher.decryptions, 0);
      expect(await nodes.readAsString(), '$history\n');
      expect(history, isNot(contains(privateText)));

      final allReading = Completer<void>();
      final release = Completer<void>();
      var readers = 0;
      var cancelled = 0;
      Stream<List<int>> pausedRead() async* {
        try {
          yield utf8.encode('$history\n');
          if (++readers == 3) allReading.complete();
          await release.future;
          yield utf8.encode('$history\n');
        } finally {
          cancelled++;
        }
      }

      await IOOverrides.runZoned(
        () async {
          expect(await graph.recentNodes(limit: 0), isEmpty);
          expect(await graph.nodesOlderThan(end, limit: -1), isEmpty);
          expect(await graph.nodesBetween(start, end, limit: 0), isEmpty);
          expect(readers, 0);

          final pending = [
            graph.recentNodes(limit: 4),
            graph.nodesOlderThan(end, limit: 2),
            graph.nodesBetween(start, end, limit: 3),
          ];
          try {
            await allReading.future.timeout(const Duration(seconds: 5));
            await graph.resetAfterDataWipe();
          } finally {
            release.complete();
          }
          for (final result in await Future.wait(pending)) {
            expect(result, isEmpty);
          }
          expect(cancelled, 3);
          expect(cipher.decryptions, 0);
        },
        createFile: (path) {
          expect(path, nodes.path);
          return _PausedNodesFile(nodes, pausedRead());
        },
      );

      expect(await nodes.exists(), isFalse);
      expect(await graph.recentNodes(), isEmpty);
      expect(await graph.nodesOlderThan(end), isEmpty);
      expect(await graph.nodesBetween(start, end), isEmpty);
      await expectLater(
        graph.logUserAction(kind: 'fixture', payload: {'text': privateText}),
        throwsStateError,
      );
      expect(await nodes.parent.exists(), isFalse);
    },
  );
}
