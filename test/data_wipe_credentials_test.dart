import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_model_credentials.dart';
import 'package:neuro_companion/services/neura_model_types.dart';
import 'package:neuro_companion/services/neura_provider_credentials.dart';

class _CredentialStore
    implements NeuraCredentialStorage, NeuraModelCredentialStorage {
  final values = <String, String>{};
  bool ignoreDeletes = false;
  Completer<void>? readStarted;
  Completer<void>? releaseRead;

  @override
  Future<String?> read({required String key}) async {
    final value = values[key];
    final started = readStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
      await releaseRead!.future;
    }
    return value;
  }

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    if (!ignoreDeletes) values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed full-wipe deletion still revokes the cached provider key',
      () async {
    final storage = _CredentialStore();
    final credentials = NeuraProviderCredentials.forTesting(storage: storage);
    await credentials.save('sk-ant-synthetic-provider-credential-fixture');
    storage.ignoreDeletes = true;
    final clear = credentials.clearForDataWipe();
    final outcome = expectLater(clear, throwsStateError);
    expect(credentials.apiKey, isEmpty);
    expect(credentials.hasKey, isFalse);
    expect(credentials.configured.value, isFalse);
    await outcome;
    expect(credentials.apiKey, isEmpty);
    await expectLater(credentials.initialize(), throwsStateError);
    await expectLater(
        credentials.save('sk-ant-synthetic-provider-credential-fixture'),
        throwsStateError);
    storage.ignoreDeletes = false;
    await credentials.clearForDataWipe();
    await credentials.clearForDataWipe();
    final restarted = NeuraProviderCredentials.forTesting(
        storage: storage,
        legacyBuildKey: 'sk-ant-synthetic-provider-credential-fixture');
    await restarted.initialize();
    expect(restarted.hasKey, isFalse);
  });

  test(
      'failed full-wipe model deletion prevents reads and clears configuration',
      () async {
    final storage = _CredentialStore();
    final credentials = NeuraModelCredentials.forTesting(storage);
    await credentials.save(
        NeuraModelProvider.openAi, 'sk-synthetic-model-credential-fixture');
    storage.ignoreDeletes = true;
    await expectLater(credentials.clearForDataWipe(), throwsStateError);
    expect(credentials.configured.value, isEmpty);
    await expectLater(
        credentials.read(NeuraModelProvider.openAi), throwsStateError);
    await expectLater(credentials.initialize(), throwsStateError);
    await expectLater(
        credentials.save(
            NeuraModelProvider.openAi, 'sk-synthetic-model-credential-fixture'),
        throwsStateError);
    storage.ignoreDeletes = false;
    await credentials.clearForDataWipe();
    expect(storage.values, isEmpty);
  });

  test('a model read started before wipe cannot return its revoked secret',
      () async {
    final storage = _CredentialStore();
    final credentials = NeuraModelCredentials.forTesting(storage);
    await credentials.save(
        NeuraModelProvider.openAi, 'sk-synthetic-model-credential-fixture');
    storage.readStarted = Completer<void>();
    storage.releaseRead = Completer<void>();
    addTearDown(() {
      if (!storage.releaseRead!.isCompleted) storage.releaseRead!.complete();
    });
    final readOutcome = expectLater(
        credentials.read(NeuraModelProvider.openAi), throwsStateError);
    await storage.readStarted!.future;
    await credentials.clearForDataWipe();
    storage.releaseRead!.complete();
    await readOutcome;
    expect(storage.values, isEmpty);
  });
}
