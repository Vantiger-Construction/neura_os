import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_session_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';

import 'data_wipe_fixture.dart';

// Each caller runs in its own isolate: full-wipe suspension is terminal.
void registerHeldScopedWipeTest(String operation) {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('full wipe bounds held native $operation and retains deletion failure',
      () async {
    final f = await DataWipeFixture.create();
    await f.run(() async {
      final now = DateTime.utc(2026, 10, 19, 12);
      final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
      final scope = EncryptedMemoryAccessScope(
        ownerId: 'owner',
        deviceId: 'device',
        capsuleId: 'personal',
        classes: const {EncryptedMemoryClass.explicitPreference},
        sources: const {EncryptedMemorySource.authenticatedUser},
        sensitivity: EncryptedMemorySensitivity.personal,
      );
      EncryptedMemoryConsentLease consent(
              String id, EncryptedMemoryOperation op) =>
          EncryptedMemoryConsentLease(
            id: id,
            scope: scope,
            operations: {op},
            issuedAtUtc: now,
            expiresAtUtc: now.add(const Duration(minutes: 5)),
            directUserGesture: true,
          );
      const context = NeuraSafetyContext(directUserGesture: true);
      final crypto = await MemoryCrypto.demo();
      final subject = EncryptedMemoryDurableScopedAdapter(
        safetyPolicy: NeuraLivingSafetyPolicy(),
        keyLifecycle: keys,
        loadCrypto: () async => MemoryCryptoDurableAdapter(crypto),
        utcNow: () => now,
      );

      const storage = EncryptedMemoryDurableScopedAdapter.defaultStorageKey;
      const nativeStorage = 'flutter.$storage';
      final started = Completer<void>();
      final release = Completer<void>();
      final lateRemoved = Completer<void>();
      var heldOnce = false;
      Future<void> hold() async {
        if (heldOnce) return;
        heldOnce = true;
        started.complete();
        await release.future;
      }

      if (operation == 'setString') {
        f.preferences.beforeSet = (key) async {
          if (key == nativeStorage) await hold();
        };
      }
      final pending = subject.remember(
        lease: consent('remember', EncryptedMemoryOperation.remember),
        safetyContext: context,
        record: EncryptedMemorySessionRecord(
          id: 'record',
          ownerId: 'owner',
          deviceId: 'device',
          capsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          sensitivity: EncryptedMemorySensitivity.personal,
          provenance: EncryptedMemoryProvenance(
            source: EncryptedMemorySource.authenticatedUser,
            sourceId: 'synthetic-gesture',
            authorId: 'owner',
            reason: 'user_tapped_remember',
            trustTier: EncryptedMemoryTrustTier.authenticatedUser,
            integrityState: EncryptedMemoryIntegrityState.verified,
            integrityTag: 'sha256:0123456789abcdef',
            observedAtUtc: now,
          ),
          value: 'synthetic private record',
          createdAtUtc: now,
          keyGeneration: keys.generation,
        ),
        expectedKeyGeneration: keys.generation,
        nowUtc: now,
      );

      Future<void>? rejected;
      if (operation == 'setString') {
        rejected = expectLater(
            pending, throwsA(isA<EncryptedMemoryPolicyViolation>()));
        await started.future;
      } else {
        await pending;
        if (operation == 'remove') {
          f.preferences.beforeRemove = (key) async {
            if (key == nativeStorage) await hold();
          };
        } else {
          f.preferences.beforeGetAll = hold;
        }
      }
      f.ignoredSecretDeletes.add(DataWipeFixture.memoryKey);
      final wipe = NeuraDataWipeService.wipeAllLocalData();
      await started.future.timeout(const Duration(seconds: 10));
      try {
        await expectLater(
          wipe.timeout(const Duration(seconds: 12)),
          throwsA(isA<NeuraDataWipeException>().having(
            (e) => e.failedSteps,
            'failed steps',
            containsAll([
              'scoped memory writer shutdown',
              'device encryption key deletion',
            ]),
          )),
        );
        expect(f.deletedSecretKeys, contains(DataWipeFixture.memoryKey));
        expect(keys.state, EncryptedMemoryKeyState.suspended);
        expect(SafeBoot.instance.safeMode.value, isTrue);
      } finally {
        f.preferences.beforeGetAll = null;
        f.preferences.beforeRemove = (key) async {
          if (key == nativeStorage && !lateRemoved.isCompleted) {
            lateRemoved.complete();
          }
        };
        release.complete();
      }
      if (rejected != null) await rejected;
      await lateRemoved.future.timeout(const Duration(seconds: 5));
      // The callback above runs before the removal; await the store turn too.
      await Future<void>.delayed(Duration.zero);
      expect(f.preferences.data.containsKey(nativeStorage), isFalse);
      expect(subject.recordCount, 0);
      f.ignoredSecretDeletes.clear();
      await NeuraDataWipeService.wipeAllLocalData();
      expect(keys.state, EncryptedMemoryKeyState.destroyed);
      expect(f.secrets.containsKey(DataWipeFixture.memoryKey), isFalse);
      await expectLater(
          crypto.encryptJson({'late': 'synthetic'}), throwsStateError);
      f.expectIsolation();
    });
  });
}
