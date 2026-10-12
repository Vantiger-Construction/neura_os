import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_session_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Tests install fake SharedPreferences platform stores directly.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final secureValues = <String, String>{};
  final issuedAt = DateTime.utc(2026, 10, 11, 12);
  const context = NeuraSafetyContext(directUserGesture: true);
  late _FakeDurableCrypto crypto;
  late EncryptedMemoryKeyLifecycle keys;
  late NeuraLivingSafetyPolicy safety;

  setUpAll(() async {
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

  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      null,
    );
  });

  setUp(() async {
    secureValues.clear();
    await NeuraPrefsCache.prefs.clear();
    EncryptedMemoryDurableScopedAdapter.debugResetStorageRegistryForTesting();
    crypto = _FakeDurableCrypto();
    keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    safety = NeuraLivingSafetyPolicy(safeModeReader: () => false);
  });

  EncryptedMemoryDurableScopedAdapter adapter() {
    return EncryptedMemoryDurableScopedAdapter(
      safetyPolicy: safety,
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
  ) =>
      EncryptedMemoryConsentLease(
        id: id,
        scope: scope(),
        operations: {operation},
        issuedAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
        directUserGesture: true,
      );

  EncryptedMemorySessionRecord record({
    String id = 'record-1',
    String value = 'Prefers concise text.',
  }) {
    return EncryptedMemorySessionRecord(
      id: id,
      ownerId: 'owner-1',
      deviceId: 'device-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      sensitivity: EncryptedMemorySensitivity.personal,
      provenance: EncryptedMemoryProvenance(
        source: EncryptedMemorySource.authenticatedUser,
        sourceId: 'source-$id',
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
    String recordId = 'record-1',
    String deviceId = 'device-1',
  }) {
    return subject.recall(
      lease: recallLease,
      safetyContext: context,
      recordId: recordId,
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

  test(
    'default crypto authority restores and can write after empty durable state',
    () async {
      final subject = EncryptedMemoryDurableScopedAdapter(
        safetyPolicy: safety,
        keyLifecycle: keys,
      );
      await subject.remember(
        lease: lease('remember-1', EncryptedMemoryOperation.remember),
        safetyContext: context,
        record: record(),
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      );

      final restarted = EncryptedMemoryDurableScopedAdapter(
        safetyPolicy: safety,
        keyLifecycle: keys,
      );
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

      expect(
        await restarted.forget(
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
          nowUtc: issuedAt.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );
      expect(
        NeuraPrefsCache.prefs.containsKey(
          EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
        ),
        isFalse,
      );

      await restarted.remember(
        lease: lease('remember-2', EncryptedMemoryOperation.remember),
        safetyContext: context,
        record: record(id: 'record-2', value: 'Prefers evening walks.'),
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 3)),
      );
      final afterEmptyRestart = EncryptedMemoryDurableScopedAdapter(
        safetyPolicy: safety,
        keyLifecycle: keys,
      );
      await afterEmptyRestart.restore(
        safetyContext: context,
        expectedKeyGeneration: keys.generation,
      );
      expect(
        recall(
          afterEmptyRestart,
          lease('recall-2', EncryptedMemoryOperation.recall),
          recordId: 'record-2',
        )?.value,
        'Prefers evening walks.',
      );
    },
  );

  test('fresh crypto wrappers with the same authority token can continue',
      () async {
    final inner = _FakeDurableCrypto();
    final authority = Object();
    EncryptedMemoryDurableCrypto freshWrapper() =>
        _FreshWrapperDurableCrypto(inner, authority);
    final subject = EncryptedMemoryDurableScopedAdapter(
      safetyPolicy: safety,
      keyLifecycle: keys,
      loadCrypto: () async => freshWrapper(),
    );
    await subject.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    final restarted = EncryptedMemoryDurableScopedAdapter(
      safetyPolicy: safety,
      keyLifecycle: keys,
      loadCrypto: () async => freshWrapper(),
    );
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

    expect(
      await restarted.forget(
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
        nowUtc: issuedAt.add(const Duration(seconds: 2)),
      ),
      isTrue,
    );
    await restarted.remember(
      lease: lease('remember-2', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(id: 'record-2', value: 'Prefers evening walks.'),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 3)),
    );

    final secondRestart = EncryptedMemoryDurableScopedAdapter(
      safetyPolicy: safety,
      keyLifecycle: keys,
      loadCrypto: () async => freshWrapper(),
    );
    await secondRestart.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );
    expect(
      recall(
        secondRestart,
        lease('recall-2', EncryptedMemoryOperation.recall),
        recordId: 'record-2',
      )?.value,
      'Prefers evening walks.',
    );
  });

  test('successive durable writes use distinct ciphertext envelopes', () async {
    final subject = adapter();
    await subject.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );
    final firstBlob = NeuraPrefsCache.prefs.getString(
      EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
    )!;

    await subject.correct(
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
    final secondBlob = NeuraPrefsCache.prefs.getString(
      EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
    )!;

    expect(firstBlob, isNot(secondBlob));
    expect(secondBlob, isNot(contains('Prefers detailed text.')));
  });

  test('restart fails closed when the key generation changed', () async {
    final first = adapter();
    await first.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );
    keys
      ..beginRotation()
      ..commitVerifiedRotation();

    await expectLater(
      adapter().restore(
        safetyContext: context,
        expectedKeyGeneration: keys.generation,
      ),
      throwsA(
        isA<EncryptedMemoryPolicyViolation>().having(
          (error) => error.code,
          'code',
          'record_key_generation_mismatch',
        ),
      ),
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
        destroyKey: false,
        verifyCiphertextDeletion: true,
        verifyKeyDeletion: false,
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

  test('scoped wipe rejects shared-key destruction claims', () async {
    final subject = adapter();
    await subject.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    await expectLater(
      subject.wipeScope(
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
      ),
      throwsA(
        isA<EncryptedMemoryPolicyViolation>().having(
          (error) => error.code,
          'code',
          'scoped_wipe_cannot_destroy_shared_key',
        ),
      ),
    );
    expect(subject.recordCount, 1);
  });

  test('delayed remember cannot resurrect after queued forget and restart',
      () async {
    final delayedCrypto = _BlockingDurableCrypto();
    final subject = EncryptedMemoryDurableScopedAdapter(
      safetyPolicy: safety,
      keyLifecycle: keys,
      loadCrypto: () async => delayedCrypto,
    );

    final remember = subject.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );
    await delayedCrypto.waitForFirstEncrypt();
    final forget = subject.forget(
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
      nowUtc: issuedAt.add(const Duration(seconds: 2)),
    );
    delayedCrypto.releaseFirstEncrypt();

    await remember;
    expect(await forget, isTrue);
    final restarted = EncryptedMemoryDurableScopedAdapter(
      safetyPolicy: safety,
      keyLifecycle: keys,
      loadCrypto: () async => delayedCrypto,
    );
    await restarted.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );
    expect(
      recall(restarted, lease('recall-1', EncryptedMemoryOperation.recall)),
      isNull,
    );
  });

  test('delayed restore cannot resurrect after queued wipe and next write',
      () async {
    final delayedCrypto = _BlockingDecryptDurableCrypto();
    crypto = delayedCrypto;
    final seeded = adapter();
    await seeded.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    final subject = adapter();
    final restore = subject.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );
    await delayedCrypto.waitForFirstDecrypt();
    final wipe = subject.wipeScope(
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
        destroyKey: false,
        verifyCiphertextDeletion: true,
        verifyKeyDeletion: false,
      ),
    );
    delayedCrypto.releaseFirstDecrypt();

    await restore;
    await wipe;
    expect(subject.recordCount, 0);

    await subject.remember(
      lease: lease('remember-2', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(id: 'record-2', value: 'Prefers evening walks.'),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 3)),
    );

    final restarted = adapter();
    await restarted.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );
    expect(
      recall(restarted, lease('recall-1', EncryptedMemoryOperation.recall)),
      isNull,
    );
    expect(restarted.recordCount, 1);
    expect(
      recall(
        restarted,
        lease('recall-2', EncryptedMemoryOperation.recall),
        recordId: 'record-2',
      )?.value,
      'Prefers evening walks.',
    );
  });

  test('sibling adapters cannot persist a forgotten stale record', () async {
    final seeded = adapter();
    await seeded.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    final first = adapter();
    await first.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );
    final second = adapter();
    await second.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );

    expect(
      await first.forget(
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
        nowUtc: issuedAt.add(const Duration(seconds: 2)),
      ),
      isTrue,
    );
    await second.remember(
      lease: lease('remember-2', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(id: 'record-2', value: 'Prefers evening walks.'),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 3)),
    );

    final restarted = adapter();
    await restarted.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );
    expect(
      recall(restarted, lease('recall-1', EncryptedMemoryOperation.recall)),
      isNull,
    );
    expect(restarted.recordCount, 1);
  });

  test(
    'wrong lifecycle or unattached crypto cannot read shared plaintext',
    () async {
      final subject = adapter();
      await subject.remember(
        lease: lease('remember-1', EncryptedMemoryOperation.remember),
        safetyContext: context,
        record: record(),
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      );

      final wrongKeys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
      final wrongLifecycle = EncryptedMemoryDurableScopedAdapter(
        safetyPolicy: safety,
        keyLifecycle: wrongKeys,
        loadCrypto: () async => _ThrowingDurableCrypto(),
      );
      final wrongLease = EncryptedMemoryConsentLease(
        id: 'recall-wrong-lifecycle',
        scope: scope(),
        operations: const {EncryptedMemoryOperation.recall},
        issuedAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
        directUserGesture: true,
      );

      expect(
        () => wrongLifecycle.recall(
          lease: wrongLease,
          safetyContext: context,
          recordId: 'record-1',
          ownerId: 'owner-1',
          deviceId: 'device-1',
          capsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          source: EncryptedMemorySource.authenticatedUser,
          sensitivity: EncryptedMemorySensitivity.personal,
          expectedKeyGeneration: wrongKeys.generation,
          nowUtc: issuedAt.add(const Duration(seconds: 2)),
        ),
        throwsA(
          isA<EncryptedMemoryPolicyViolation>().having(
            (error) => error.code,
            'code',
            'durable_authority_mismatch',
          ),
        ),
      );

      final wrongCrypto = EncryptedMemoryDurableScopedAdapter(
        safetyPolicy: safety,
        keyLifecycle: keys,
        loadCrypto: () async => _ThrowingDurableCrypto(),
      );
      expect(
        () => recall(
          wrongCrypto,
          lease('recall-wrong-crypto', EncryptedMemoryOperation.recall),
        ),
        throwsA(
          isA<EncryptedMemoryPolicyViolation>().having(
            (error) => error.code,
            'code',
            'durable_authority_mismatch',
          ),
        ),
      );

      keys.suspend();
      expect(
        () => recall(
          subject,
          lease('recall-suspended-owner', EncryptedMemoryOperation.recall),
        ),
        throwsA(
          isA<EncryptedMemoryPolicyViolation>().having(
            (error) => error.code,
            'code',
            'key_not_usable',
          ),
        ),
      );
    },
  );

  test('commit-time safe mode blocks a stale pending durable write', () async {
    var safeMode = false;
    final delayedCrypto = _BlockingDurableCrypto();
    final subject = EncryptedMemoryDurableScopedAdapter(
      safetyPolicy: NeuraLivingSafetyPolicy(safeModeReader: () => safeMode),
      keyLifecycle: keys,
      loadCrypto: () async => delayedCrypto,
    );

    final remember = subject.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );
    await delayedCrypto.waitForFirstEncrypt();
    safeMode = true;
    delayedCrypto.releaseFirstEncrypt();

    await expectLater(
      remember,
      throwsA(
        isA<EncryptedMemoryPolicyViolation>().having(
          (error) => error.code,
          'code',
          'safe_mode_blocked',
        ),
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

  test(
    'committed write followed by reload failure requires reconciliation',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final platform = _ReloadFailingAfterSetPreferencesStore();
      SharedPreferencesStorePlatform.instance = platform;
      await NeuraPrefsCache.prefs.reload();
      try {
        final subject = adapter();
        await expectLater(
          subject.remember(
            lease: lease('remember-1', EncryptedMemoryOperation.remember),
            safetyContext: context,
            record: record(),
            expectedKeyGeneration: keys.generation,
            nowUtc: issuedAt.add(const Duration(seconds: 1)),
          ),
          throwsA(isA<StateError>()),
        );

        await expectLater(
          subject.forget(
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
            nowUtc: issuedAt.add(const Duration(seconds: 2)),
          ),
          throwsA(
            isA<EncryptedMemoryPolicyViolation>().having(
              (error) => error.code,
              'code',
              'durable_reconciliation_required',
            ),
          ),
        );

        await subject.restore(
          safetyContext: context,
          expectedKeyGeneration: keys.generation,
        );
        expect(subject.recordCount, 1);
        expect(
          await subject.forget(
            lease: lease('forget-2', EncryptedMemoryOperation.forget),
            safetyContext: context,
            recordId: 'record-1',
            ownerId: 'owner-1',
            deviceId: 'device-1',
            capsuleId: 'personal',
            memoryClass: EncryptedMemoryClass.explicitPreference,
            source: EncryptedMemorySource.authenticatedUser,
            sensitivity: EncryptedMemorySensitivity.personal,
            expectedKeyGeneration: keys.generation,
            nowUtc: issuedAt.add(const Duration(seconds: 3)),
          ),
          isTrue,
        );
        final restarted = adapter();
        await restarted.restore(
          safetyContext: context,
          expectedKeyGeneration: keys.generation,
        );
        expect(restarted.recordCount, 0);
      } finally {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.setMockInitialValues({});
        await NeuraPrefsCache.prefs.reload();
      }
    },
  );

  test(
    'failed remove and failed reload keep reconciliation through construction',
    () async {
      final subject = adapter();
      await subject.remember(
        lease: lease('remember-1', EncryptedMemoryOperation.remember),
        safetyContext: context,
        record: record(),
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      );
      final blob = NeuraPrefsCache.prefs.getString(
        EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
      )!;
      final original = SharedPreferencesStorePlatform.instance;
      final platform = _RemoveRetainingReloadFailingPreferencesStore({
        'flutter.${EncryptedMemoryDurableScopedAdapter.defaultStorageKey}':
            blob,
      });
      SharedPreferencesStorePlatform.instance = platform;
      try {
        await expectLater(
          subject.forget(
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
            nowUtc: issuedAt.add(const Duration(seconds: 2)),
          ),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          subject.restore(
            safetyContext: context,
            expectedKeyGeneration: keys.generation,
          ),
          throwsA(isA<StateError>()),
        );

        final sibling = adapter();
        await expectLater(
          sibling.forget(
            lease: lease('forget-sibling', EncryptedMemoryOperation.forget),
            safetyContext: context,
            recordId: 'record-1',
            ownerId: 'owner-1',
            deviceId: 'device-1',
            capsuleId: 'personal',
            memoryClass: EncryptedMemoryClass.explicitPreference,
            source: EncryptedMemorySource.authenticatedUser,
            sensitivity: EncryptedMemorySensitivity.personal,
            expectedKeyGeneration: keys.generation,
            nowUtc: issuedAt.add(const Duration(seconds: 3)),
          ),
          throwsA(
            isA<EncryptedMemoryPolicyViolation>().having(
              (error) => error.code,
              'code',
              'durable_reconciliation_required',
            ),
          ),
        );

        platform.failReload = false;
        platform.retainOnRemove = false;
        await subject.restore(
          safetyContext: context,
          expectedKeyGeneration: keys.generation,
        );
        expect(subject.recordCount, 1);
        expect(
          await subject.forget(
            lease: lease('forget-2', EncryptedMemoryOperation.forget),
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
          ),
          isTrue,
        );
      } finally {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.setMockInitialValues({});
        await NeuraPrefsCache.prefs.reload();
      }
    },
  );

  test('failed durable remove rolls back memory and leaves restart restorable',
      () async {
    final subject = adapter();
    await subject.remember(
      lease: lease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: record(),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );
    final blob = NeuraPrefsCache.prefs.getString(
      EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
    )!;
    final original = SharedPreferencesStorePlatform.instance;
    final platform = _RemoveFailingPreferencesStore({
      'flutter.${EncryptedMemoryDurableScopedAdapter.defaultStorageKey}': blob,
    });
    SharedPreferencesStorePlatform.instance = platform;
    await NeuraPrefsCache.prefs.reload();
    try {
      await expectLater(
        subject.forget(
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
          nowUtc: issuedAt.add(const Duration(seconds: 2)),
        ),
        throwsA(
          isA<EncryptedMemoryPolicyViolation>().having(
            (error) => error.code,
            'code',
            'durable_remove_failed',
          ),
        ),
      );
      expect(subject.recordCount, 1);
      final restarted = adapter();
      await restarted.restore(
        safetyContext: context,
        expectedKeyGeneration: keys.generation,
      );
      expect(restarted.recordCount, 1);
    } finally {
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.setMockInitialValues({});
      await NeuraPrefsCache.prefs.reload();
    }
  });

  test('invalid quarantine release keeps the candidate for later review',
      () async {
    final subject = adapter();
    EncryptedMemoryConsentLease modelOutputLease(
      String id,
      EncryptedMemoryOperation operation,
    ) =>
        EncryptedMemoryConsentLease(
          id: id,
          scope: EncryptedMemoryAccessScope(
            ownerId: 'owner-1',
            deviceId: 'device-1',
            capsuleId: 'personal',
            classes: const {EncryptedMemoryClass.explicitPreference},
            sources: const {EncryptedMemorySource.modelOutput},
            sensitivity: EncryptedMemorySensitivity.personal,
          ),
          operations: {operation},
          issuedAtUtc: issuedAt,
          expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
          directUserGesture: true,
        );
    final quarantined = EncryptedMemorySessionRecord(
      id: 'record-1',
      ownerId: 'owner-1',
      deviceId: 'device-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      sensitivity: EncryptedMemorySensitivity.personal,
      provenance: EncryptedMemoryProvenance(
        source: EncryptedMemorySource.modelOutput,
        sourceId: 'source-1',
        authorId: 'owner-1',
        reason: 'model_candidate',
        trustTier: EncryptedMemoryTrustTier.inferred,
        integrityState: EncryptedMemoryIntegrityState.pending,
        integrityTag: null,
        observedAtUtc: issuedAt,
      ),
      value: 'Candidate preference.',
      createdAtUtc: issuedAt,
      keyGeneration: keys.generation,
    );
    await subject.remember(
      lease: modelOutputLease('remember-1', EncryptedMemoryOperation.remember),
      safetyContext: context,
      record: quarantined,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );
    expect(subject.quarantinedRecordCount, 1);

    await expectLater(
      subject.reviewQuarantined(
        lease: modelOutputLease(
          'review-1',
          EncryptedMemoryOperation.reviewQuarantine,
        ),
        safetyContext: context,
        recordId: 'record-1',
        ownerId: 'owner-1',
        deviceId: 'device-1',
        capsuleId: 'personal',
        memoryClass: EncryptedMemoryClass.explicitPreference,
        source: EncryptedMemorySource.modelOutput,
        sensitivity: EncryptedMemorySensitivity.personal,
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 2)),
        disposition: EncryptedMemoryQuarantineDisposition.release,
        verifiedIntegrityTag: 'bad',
      ),
      throwsA(
        isA<EncryptedMemoryPolicyViolation>().having(
          (error) => error.code,
          'code',
          'invalid_integrity_tag',
        ),
      ),
    );
    expect(subject.quarantinedRecordCount, 1);
  });
}

class _FakeDurableCrypto implements EncryptedMemoryDurableCrypto {
  int _nonce = 0;

  @override
  Object get authorityToken => this;

  @override
  Future<Map<String, dynamic>> decryptJson(String blob) async {
    if (!blob.startsWith('cipher:')) {
      throw const FormatException('plaintext durable memory rejected');
    }
    final envelope =
        jsonDecode(utf8.decode(base64Decode(blob.substring('cipher:'.length))))
            as Map<String, dynamic>;
    return jsonDecode(utf8.decode(base64Decode(envelope['payload'] as String)))
        as Map<String, dynamic>;
  }

  @override
  Future<String> encryptJson(Map<String, dynamic> json) async {
    final envelope = {
      'nonce': 'nonce-${++_nonce}',
      'payload': base64Encode(utf8.encode(jsonEncode(json))),
    };
    return 'cipher:${base64Encode(utf8.encode(jsonEncode(envelope)))}';
  }
}

final class _FreshWrapperDurableCrypto implements EncryptedMemoryDurableCrypto {
  const _FreshWrapperDurableCrypto(this.inner, this.authorityToken);

  final _FakeDurableCrypto inner;

  @override
  final Object authorityToken;

  @override
  Future<Map<String, dynamic>> decryptJson(String blob) =>
      inner.decryptJson(blob);

  @override
  Future<String> encryptJson(Map<String, dynamic> json) =>
      inner.encryptJson(json);
}

final class _BlockingDurableCrypto extends _FakeDurableCrypto {
  final _started = Completer<void>();
  final _release = Completer<void>();
  bool _blocked = false;

  Future<void> waitForFirstEncrypt() => _started.future;

  void releaseFirstEncrypt() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<String> encryptJson(Map<String, dynamic> json) async {
    if (!_blocked) {
      _blocked = true;
      _started.complete();
      await _release.future;
    }
    return super.encryptJson(json);
  }
}

final class _BlockingDecryptDurableCrypto extends _FakeDurableCrypto {
  final _started = Completer<void>();
  final _release = Completer<void>();
  bool _blocked = false;

  Future<void> waitForFirstDecrypt() => _started.future;

  void releaseFirstDecrypt() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<Map<String, dynamic>> decryptJson(String blob) async {
    if (!_blocked) {
      _blocked = true;
      _started.complete();
      await _release.future;
    }
    return super.decryptJson(blob);
  }
}

final class _ThrowingDurableCrypto implements EncryptedMemoryDurableCrypto {
  @override
  Object get authorityToken => this;

  @override
  Future<Map<String, dynamic>> decryptJson(String blob) async {
    throw StateError('synthetic wrong crypto');
  }

  @override
  Future<String> encryptJson(Map<String, dynamic> json) async {
    throw StateError('synthetic wrong crypto');
  }
}

final class _ReloadFailingAfterSetPreferencesStore
    extends SharedPreferencesStorePlatform {
  final Map<String, Object> data = {};
  bool failNextReload = false;

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (failNextReload) {
      failNextReload = false;
      throw StateError('synthetic reload failure');
    }
    return Map<String, Object>.from(data);
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    data[key] = value;
    failNextReload = true;
    return true;
  }
}

final class _RemoveFailingPreferencesStore
    extends SharedPreferencesStorePlatform {
  _RemoveFailingPreferencesStore(Map<String, Object> seed)
      : data = Map<String, Object>.from(seed);

  final Map<String, Object> data;

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.from(data);

  @override
  Future<bool> remove(String key) async => false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    data[key] = value;
    return true;
  }
}

final class _RemoveRetainingReloadFailingPreferencesStore
    extends SharedPreferencesStorePlatform {
  _RemoveRetainingReloadFailingPreferencesStore(Map<String, Object> seed)
      : data = Map<String, Object>.from(seed);

  final Map<String, Object> data;
  bool failReload = true;
  bool retainOnRemove = true;

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (failReload) throw StateError('synthetic reload failure');
    return Map<String, Object>.from(data);
  }

  @override
  Future<bool> remove(String key) async {
    if (!retainOnRemove) data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    data[key] = value;
    return true;
  }
}
