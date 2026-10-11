import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_session_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 10, 11, 12);
  const context = NeuraSafetyContext(directUserGesture: true);
  late _FakeDurableCrypto crypto;
  late EncryptedMemoryKeyLifecycle keys;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    await NeuraPrefsCache.prefs.clear();
    crypto = _FakeDurableCrypto();
    keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
  });

  EncryptedMemoryDurableScopedAdapter adapter() {
    return EncryptedMemoryDurableScopedAdapter(
      safetyPolicy: NeuraLivingSafetyPolicy(safeModeReader: () => false),
      keyLifecycle: keys,
      loadCrypto: () async => crypto,
    );
  }

  EncryptedMemoryAccessScope scope() => EncryptedMemoryAccessScope(
    ownerId: 'owner-1',
    deviceId: 'device-1',
    capsuleId: 'personal',
    classes: const {EncryptedMemoryClass.explicitPreference},
    sources: const {EncryptedMemorySource.authenticatedUser},
    sensitivity: EncryptedMemorySensitivity.personal,
  );

  EncryptedMemoryConsentLease lease(
    String id,
    EncryptedMemoryOperation operation,
  ) => EncryptedMemoryConsentLease(
    id: id,
    scope: scope(),
    operations: {operation},
    issuedAtUtc: issuedAt,
    expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
    directUserGesture: true,
  );

  EncryptedMemorySessionRecord record({
    String value = 'Prefers concise text.',
  }) {
    return EncryptedMemorySessionRecord(
      id: 'record-1',
      ownerId: 'owner-1',
      deviceId: 'device-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      sensitivity: EncryptedMemorySensitivity.personal,
      provenance: EncryptedMemoryProvenance(
        source: EncryptedMemorySource.authenticatedUser,
        sourceId: 'source-1',
        authorId: 'owner-1',
        reason: 'user_tapped_remember',
        trustTier: EncryptedMemoryTrustTier.authenticatedUser,
        integrityState: EncryptedMemoryIntegrityState.verified,
        integrityTag: 'sha256:0123456789abcdef',
        observedAtUtc: issuedAt,
      ),
      value: value,
      createdAtUtc: issuedAt,
      keyGeneration: keys.generation,
    );
  }

  EncryptedMemorySessionRecord? recall(
    EncryptedMemoryDurableScopedAdapter subject,
    EncryptedMemoryConsentLease recallLease, {
    String deviceId = 'device-1',
  }) {
    return subject.recall(
      lease: recallLease,
      safetyContext: context,
      recordId: 'record-1',
      ownerId: 'owner-1',
      deviceId: deviceId,
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      source: EncryptedMemorySource.authenticatedUser,
      sensitivity: EncryptedMemorySensitivity.personal,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 2)),
    );
  }

  test('remember persists encrypted-only and restores after restart', () async {
    final first = adapter();
    await first.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    final blob = NeuraPrefsCache.prefs.getString(
      EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
    )!;
    expect(blob, startsWith('cipher:'));
    expect(blob, isNot(contains('Prefers concise text')));

    final restarted = adapter();
    await restarted.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );
    expect(
      recall(
        restarted,
        lease('recall-1', EncryptedMemoryOperation.recall),
      )?.value,
      'Prefers concise text.',
    );
  });

  test('correction and forget are exact-scope single-use operations', () async {
    final subject = adapter();
    await subject.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    final corrected = await subject.correct(
      lease: lease('correct-1', EncryptedMemoryOperation.correct),
      safetyContext: context,
      recordId: 'record-1',
      ownerId: 'owner-1',
      deviceId: 'device-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      source: EncryptedMemorySource.authenticatedUser,
      sensitivity: EncryptedMemorySensitivity.personal,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 2)),
      replacementValue: 'Prefers detailed text.',
    );
    expect(corrected, isTrue);
    expect(
      recall(
        subject,
        lease('recall-1', EncryptedMemoryOperation.recall),
      )?.value,
      'Prefers detailed text.',
    );

    final forgotten = await subject.forget(
      lease: lease('forget-1', EncryptedMemoryOperation.forget),
      safetyContext: context,
      recordId: 'record-1',
      ownerId: 'owner-1',
      deviceId: 'device-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      source: EncryptedMemorySource.authenticatedUser,
      sensitivity: EncryptedMemorySensitivity.personal,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 4)),
    );
    expect(forgotten, isTrue);
    expect(
      recall(subject, lease('recall-2', EncryptedMemoryOperation.recall)),
      isNull,
    );
  });

  test(
    'wrong owner or device fails before returning durable content',
    () async {
      final subject = adapter();
      await subject.remember(
        lease: lease('remember-1', EncryptedMemoryOperation.remember),
        safetyContext: context,
        record: record(),
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      );
      final wrongLease = EncryptedMemoryConsentLease(
        id: 'recall-wrong-device',
        scope: EncryptedMemoryAccessScope(
          ownerId: 'owner-1',
          deviceId: 'device-2',
          capsuleId: 'personal',
          classes: const {EncryptedMemoryClass.explicitPreference},
          sources: const {EncryptedMemorySource.authenticatedUser},
          sensitivity: EncryptedMemorySensitivity.personal,
        ),
        operations: const {EncryptedMemoryOperation.recall},
        issuedAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
        directUserGesture: true,
      );

      expect(
        () => recall(subject, wrongLease),
        throwsA(
          isA<EncryptedMemoryPolicyViolation>().having(
            (error) => error.code,
            'code',
            'consent_not_authorized',
          ),
        ),
      );
    },
  );

  test('scoped wipe removes matching durable records only', () async {
    final subject = adapter();
    await subject.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    await subject.wipeScope(
      lease: lease('wipe-1', EncryptedMemoryOperation.wipe),
      safetyContext: context,
      ownerId: 'owner-1',
      deviceId: 'device-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      source: EncryptedMemorySource.authenticatedUser,
      sensitivity: EncryptedMemorySensitivity.personal,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 2)),
      contract: const EncryptedMemoryWipeContract(
        stopWritersFirst: true,
        deleteCiphertext: true,
        destroyKey: true,
        verifyCiphertextDeletion: true,
        verifyKeyDeletion: true,
      ),
    );

    expect(subject.recordCount, 0);
    expect(
      NeuraPrefsCache.prefs.containsKey(
        EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
      ),
      isFalse,
    );
  });
}

final class _FakeDurableCrypto implements EncryptedMemoryDurableCrypto {
  @override
  Future<Map<String, dynamic>> decryptJson(String blob) async {
    if (!blob.startsWith('cipher:')) {
      throw const FormatException('plaintext durable memory rejected');
    }
    return jsonDecode(
          utf8.decode(base64Decode(blob.substring('cipher:'.length))),
        )
        as Map<String, dynamic>;
  }

  @override
  Future<String> encryptJson(Map<String, dynamic> json) async {
    return 'cipher:${base64Encode(utf8.encode(jsonEncode(json)))}';
  }
}
