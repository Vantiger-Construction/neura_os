import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/companion_memory_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'production local owner never adopts orphaned ciphertext and reuses its verified scope',
      () async {
    final f = await CompanionMemoryFixture.create();
    await f.disk.run(() async {
      final prefs = NeuraPrefsCache.prefs;
      const key = EncryptedMemoryDurableScopedAdapter.defaultStorageKey;
      await prefs.setString(key, 'synthetic-orphaned-ciphertext');
      await expectLater(CompanionMemoryService.local(),
          throwsA(isA<EncryptedMemoryPolicyViolation>()));
      expect(prefs.getString(CompanionMemoryService.identityKey), isNull);
      await prefs.remove(key);
      // A legacy fallback may still support journal recovery, but must not
      // be silently adopted for new scoped companion records.
      await prefs.setString(
          'neura.memoryGraph.seed.v1', 'synthetic-legacy-marker');
      await expectLater(CompanionMemoryService.local(), throwsStateError);
      expect(prefs.getString(key), isNull);
      await prefs.remove('neura.memoryGraph.seed.v1');
      final service = await CompanionMemoryService.local();
      addTearDown(service.dispose);
      final id = prefs.getString(CompanionMemoryService.identityKey);
      expect(id, isNotEmpty);
      expect(service.scope.ownerId, 'local-profile:$id');
      expect(service.scope.deviceId, 'installation:$id');
      final write = service.authorize(CompanionMemoryUse.remember,
          directUserGesture: true);
      await service.remember(write, 'Synthetic production note');
      write.revoke();
      expect(
          prefs.getString(key), isNot(contains('Synthetic production note')));
      expect(await CompanionMemoryService.local(), same(service));
      final read =
          service.authorize(CompanionMemoryUse.review, directUserGesture: true);
      expect(
          (await service.recall(read, use: CompanionMemoryUse.review))
              .single
              .value,
          'Synthetic production note');
      expect(f.disk.networkAttempts, 0);
    });
  });
}
