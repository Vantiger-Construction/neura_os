import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const keyName = 'neura.memoryGraph.seed.v2';
  final secrets = <String, String>{};
  var ignoreDeletion = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return secrets[key];
        case 'write':
          secrets[key] = args['value'] as String;
          return null;
        case 'delete':
          if (!ignoreDeletion) secrets.remove(key);
          return null;
      }
      throw StateError('Unexpected synthetic secure-storage call.');
    });
    ignoreDeletion = false;
    await MemoryCrypto.clearDeviceKey();
    MemoryCrypto.resumeAfterDataWipe();
  });

  tearDown(() async {
    ignoreDeletion = false;
    await MemoryCrypto.clearDeviceKey();
    MemoryCrypto.resumeAfterDataWipe();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final operation in ['encryptJson', 'decryptJson', 'encryptBytes', 'decryptBytes']) {
    test('$operation cannot cross key destruction in the same event turn', () async {
      final crypto = await MemoryCrypto.demo();
      final json = await crypto.encryptJson({'value': 'synthetic secret'});
      final bytes = await crypto.encryptBytes(Uint8List.fromList([1, 2, 3]));
      final Future<Object> pending = switch (operation) {
        'encryptJson' => crypto.encryptJson({'value': 'synthetic secret'}),
        'decryptJson' => crypto.decryptJson(json),
        'encryptBytes' => crypto.encryptBytes(Uint8List.fromList([1, 2, 3])),
        _ => crypto.decryptBytes(bytes),
      };
      final rejected = expectLater(pending, throwsStateError);
      // No await between starting the operation and synchronously revoking its
      // generation: this targets the await on _activeKey, before AES starts.
      await MemoryCrypto.clearDeviceKey();
      await rejected;
      expect(secrets.containsKey(keyName), isFalse);
    });
  }

  test('failed key deletion blocks cached handles and retry creates a fresh authority', () async {
    final old = await MemoryCrypto.demo();
    final blob = await old.encryptJson({'value': 'synthetic private value'});
    final previousSeed = secrets[keyName];
    ignoreDeletion = true;
    await expectLater(MemoryCrypto.clearDeviceKey(), throwsStateError);
    expect(secrets[keyName], previousSeed);
    await expectLater(MemoryCrypto.demo(), throwsStateError);
    await expectLater(old.decryptJson(blob), throwsStateError);
    await expectLater(old.encryptJson({'value': 'late write'}), throwsStateError);

    ignoreDeletion = false;
    await MemoryCrypto.clearDeviceKey();
    MemoryCrypto.resumeAfterDataWipe();
    final fresh = await MemoryCrypto.demo();
    expect(secrets[keyName], isNot(previousSeed));
    final freshBlob = await fresh.encryptJson({'value': 'fresh synthetic value'});
    expect(await fresh.decryptJson(freshBlob), {'value': 'fresh synthetic value'});
    await expectLater(fresh.decryptJson(blob), throwsA(isA<Exception>()));
    await expectLater(old.decryptJson(freshBlob), throwsStateError);
    await expectLater(old.encryptJson({'value': 'stale handle'}), throwsStateError);
  });

  test('real AES-GCM rejects tampering and never persists payload or key in preferences', () async {
    final crypto = await MemoryCrypto.demo();
    const privateValue = 'synthetic private marker 20261019';
    final blob = await crypto.encryptJson({'value': privateValue});
    final envelope = jsonDecode(blob) as Map<String, dynamic>;
    final cipher = base64Decode(envelope['c'] as String);
    cipher[0] ^= 1;
    envelope['c'] = base64Encode(cipher);
    await expectLater(crypto.decryptJson(jsonEncode(envelope)), throwsA(isA<Exception>()));
    expect(await crypto.decryptJson(blob), {'value': privateValue});
    expect(blob, isNot(contains(privateValue)));
    final prefs = NeuraPrefsCache.prefs;
    final persisted = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    expect(jsonEncode(persisted), isNot(contains(privateValue)));
    expect(jsonEncode(persisted), isNot(contains(secrets[keyName]!)));
    expect(prefs.containsKey('neura.memoryGraph.seed.v1'), isFalse);
  });
}
