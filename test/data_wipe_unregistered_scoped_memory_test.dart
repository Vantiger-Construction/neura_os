import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import 'helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'cold scoped ciphertext is removed before device-key destruction without a registered owner',
      () async {
    final f = await DataWipeFixture.create();
    await f.run(() async {
      await MemoryCrypto.clearDeviceKey();
      MemoryCrypto.resumeAfterDataWipe();
      final crypto = await MemoryCrypto.demo();
      final ciphertext =
          await crypto.encryptJson({'synthetic': 'previous-process note'});
      const storage = EncryptedMemoryDurableScopedAdapter.defaultStorageKey;
      await NeuraPrefsCache.prefs.setString(storage, ciphertext);
      EncryptedMemoryDurableScopedAdapter.debugResetStorageRegistryForTesting();
      f.beforeSecretDelete = (key) async {
        if (key == DataWipeFixture.memoryKey) {
          expect(NeuraPrefsCache.prefs.containsKey(storage), false);
        }
      };
      await NeuraDataWipeService.wipeAllLocalData();
      expect(NeuraPrefsCache.prefs.containsKey(storage), false);
      expect(f.secrets.containsKey(DataWipeFixture.memoryKey), false);
      f.expectIsolation();
    });
  });
}
