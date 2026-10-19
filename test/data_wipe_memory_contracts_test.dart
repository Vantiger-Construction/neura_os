import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_session_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import 'helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Like the other full-wipe regressions, this file has a dedicated isolate.
  // Production writer/credential suspension is terminal for this process.
  test(
      'full wipe revokes a pending scoped write through failed deletion and retry',
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
      final held = _HeldMemoryCrypto(await MemoryCrypto.demo());
      final subject = EncryptedMemoryDurableScopedAdapter(
        safetyPolicy: NeuraLivingSafetyPolicy(),
        keyLifecycle: keys,
        loadCrypto: () async => held,
        utcNow: () => now,
      );
      await subject.remember(
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
      final ciphertext = NeuraPrefsCache.prefs.getString(
        EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
      )!;
      held.block = true;
      final pending = subject.correct(
        lease: consent('correct', EncryptedMemoryOperation.correct),
        safetyContext: context,
        recordId: 'record',
        ownerId: 'owner',
        deviceId: 'device',
        capsuleId: 'personal',
        memoryClass: EncryptedMemoryClass.explicitPreference,
        source: EncryptedMemorySource.authenticatedUser,
        sensitivity: EncryptedMemorySensitivity.personal,
        expectedKeyGeneration: keys.generation,
        nowUtc: now,
        replacementValue: 'synthetic late correction',
      );
      final rejected = expectLater(
          pending,
          throwsA(anyOf(
            isA<StateError>(),
            isA<EncryptedMemoryPolicyViolation>(),
          )));
      await held.started.future;
      f.ignoredSecretDeletes.add(DataWipeFixture.memoryKey);
      try {
        await expectLater(
          NeuraDataWipeService.wipeAllLocalData(),
          throwsA(isA<NeuraDataWipeException>().having(
            (e) => e.failedSteps,
            'failed steps',
            contains('device encryption key deletion'),
          )),
        );
        expect(SafeBoot.instance.safeMode.value, isTrue);
        expect(subject.recordCount, 0);
        expect(subject.quarantinedRecordCount, 0);
        expect(keys.state, EncryptedMemoryKeyState.suspended);
        await expectLater(MemoryCrypto.demo(), throwsStateError);
        expect(
            NeuraPrefsCache.prefs.containsKey(
              EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
            ),
            isFalse);
      } finally {
        held.release.complete();
      }
      await rejected;
      expect(subject.recordCount, 0);
      f.ignoredSecretDeletes.clear();
      await NeuraDataWipeService.wipeAllLocalData();
      await NeuraDataWipeService.wipeAllLocalData();
      expect(SafeBoot.instance.safeMode.value, isTrue);
      expect(keys.state, EncryptedMemoryKeyState.destroyed);
      expect(subject.recordCount, 0);
      expect(f.secrets.containsKey(DataWipeFixture.memoryKey), isFalse);
      expect(
          NeuraPrefsCache.prefs.containsKey(
            EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
          ),
          isFalse);
      await expectLater(held.inner.decryptJson(ciphertext), throwsStateError);
      await expectLater(
          held.inner.encryptJson({'value': 'late'}), throwsStateError);
      final read = consent('recall', EncryptedMemoryOperation.recall);
      expect(
          () => subject.recall(
                lease: read,
                safetyContext: context,
                recordId: 'record',
                ownerId: 'owner',
                deviceId: 'device',
                capsuleId: 'personal',
                memoryClass: EncryptedMemoryClass.explicitPreference,
                source: EncryptedMemorySource.authenticatedUser,
                sensitivity: EncryptedMemorySensitivity.personal,
                expectedKeyGeneration: keys.generation,
                nowUtc: now,
              ),
          throwsA(isA<EncryptedMemoryPolicyViolation>()));
      expect(read.isConsumed, isFalse);
      f.expectIsolation();
    });
  });
}

final class _HeldMemoryCrypto implements EncryptedMemoryDurableCrypto {
  _HeldMemoryCrypto(this.inner);

  final MemoryCrypto inner;
  final started = Completer<void>();
  final release = Completer<void>();
  bool block = false;

  @override
  Object get authorityToken {
    inner.requireActiveKey();
    return inner;
  }

  @override
  Future<String> encryptJson(Map<String, dynamic> json) async {
    if (block) {
      started.complete();
      await release.future;
    }
    return inner.encryptJson(json);
  }

  @override
  Future<Map<String, dynamic>> decryptJson(String blob) =>
      inner.decryptJson(blob);
}
