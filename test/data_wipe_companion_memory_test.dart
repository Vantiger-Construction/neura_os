import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import 'helpers/companion_memory_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual full wipe revokes production memory owners and late grants',
      () async {
    final f = await CompanionMemoryFixture.create();
    await f.disk.run(() async {
      await f.seed();
      final prompt = f.grant(CompanionMemoryUse.prompt);
      final review = f.grant(CompanionMemoryUse.review);
      await NeuraDataWipeService.wipeAllLocalData();
      expect(prompt.lease.isRevoked, true);
      expect(review.lease.isRevoked, true);
      await expectLater(f.memory.recall(review, use: CompanionMemoryUse.review),
          throwsA(isA<EncryptedMemoryPolicyViolation>()));
      expect(() => f.grant(CompanionMemoryUse.remember),
          throwsA(isA<EncryptedMemoryPolicyViolation>()));
      expect(
          NeuraPrefsCache.prefs.containsKey(
              EncryptedMemoryDurableScopedAdapter.defaultStorageKey),
          false);
      expect(f.disk.secrets, {
        'neura.anthropic_api_key.legacy_migration_disabled.v1': 'disabled',
      });
      expect(f.disk.networkAttempts, 0);
      expect(f.disk.escapedPaths, isEmpty);
    });
  });
}
