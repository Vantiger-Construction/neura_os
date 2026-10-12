import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_session_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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
      safetyPolicy: NeuraLivingSafetyPolicy(safeModeReader: () => false),
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
      safetyPolicy: NeuraLivingSafetyPolicy(safeModeReader: () => false),
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
