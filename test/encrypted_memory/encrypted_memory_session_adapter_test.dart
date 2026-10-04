import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_session_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 9, 25, 12);
  const context = NeuraSafetyContext(directUserGesture: true);

  EncryptedMemoryAccessScope scopeFor(
    EncryptedMemorySource source, {
    String ownerId = 'owner-1',
    String deviceId = 'device-1',
  }) {
    return EncryptedMemoryAccessScope(
      ownerId: ownerId,
      deviceId: deviceId,
      capsuleId: 'personal',
      classes: const {EncryptedMemoryClass.explicitPreference},
      sources: {source},
      sensitivity: EncryptedMemorySensitivity.personal,
    );
  }

  EncryptedMemoryConsentLease leaseFor(
    String id,
    EncryptedMemoryOperation operation,
    EncryptedMemorySource source, {
    String ownerId = 'owner-1',
    String deviceId = 'device-1',
  }) {
    return EncryptedMemoryConsentLease(
      id: id,
      scope: scopeFor(source, ownerId: ownerId, deviceId: deviceId),
      operations: {operation},
      issuedAtUtc: issuedAt,
      expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
      directUserGesture: true,
    );
  }

  EncryptedMemorySessionRecord recordFor(
    int generation, {
    EncryptedMemorySource source = EncryptedMemorySource.authenticatedUser,
    EncryptedMemoryTrustTier trust = EncryptedMemoryTrustTier.authenticatedUser,
    EncryptedMemoryIntegrityState integrity =
        EncryptedMemoryIntegrityState.verified,
    String? integrityTag = 'sha256:0123456789abcdef',
  }) {
    return EncryptedMemorySessionRecord(
      id: 'record-1',
      ownerId: 'owner-1',
      deviceId: 'device-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      sensitivity: EncryptedMemorySensitivity.personal,
      provenance: EncryptedMemoryProvenance(
        source: source,
        sourceId: 'source-1',
        authorId: source == EncryptedMemorySource.authenticatedUser
            ? 'owner-1'
            : 'local-model',
        reason: source == EncryptedMemorySource.authenticatedUser
            ? 'user_tapped_remember'
            : 'candidate_memory',
        trustTier: trust,
        integrityState: integrity,
        integrityTag: integrityTag,
        observedAtUtc: issuedAt,
      ),
      value: 'Prefers concise explanations.',
      createdAtUtc: issuedAt,
      keyGeneration: generation,
    );
  }

  EncryptedMemorySessionAdapter adapterFor(
    EncryptedMemoryKeyLifecycle keys, {
    bool Function()? safeModeReader,
  }) {
    return EncryptedMemorySessionAdapter(
      safetyPolicy: NeuraLivingSafetyPolicy(
        safeModeReader: safeModeReader ?? () => false,
      ),
      keyLifecycle: keys,
    );
  }

  EncryptedMemorySessionRecord? recall(
    EncryptedMemorySessionAdapter adapter,
    EncryptedMemoryKeyLifecycle keys,
    EncryptedMemoryConsentLease lease,
    EncryptedMemorySource source, {
    String recordId = 'record-1',
    String ownerId = 'owner-1',
    String deviceId = 'device-1',
    int seconds = 2,
  }) {
    return adapter.recall(
      lease: lease,
      safetyContext: context,
      recordId: recordId,
      ownerId: ownerId,
      deviceId: deviceId,
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      source: source,
      sensitivity: EncryptedMemorySensitivity.personal,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(Duration(seconds: seconds)),
    );
  }

  test('explicit remember and recall use separate exact-scope leases', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = adapterFor(keys);
    final rememberLease = leaseFor(
      'remember-1',
      EncryptedMemoryOperation.remember,
      EncryptedMemorySource.authenticatedUser,
    );

    adapter.remember(
      lease: rememberLease,
      safetyContext: context,
      record: recordFor(keys.generation),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );
    expect(rememberLease.isConsumed, isTrue);
    expect(adapter.recordCount, 1);
    expect(adapter.quarantinedRecordCount, 0);

    final recallLease = leaseFor(
      'recall-1',
      EncryptedMemoryOperation.recall,
      EncryptedMemorySource.authenticatedUser,
    );
    final recalled = recall(
      adapter,
      keys,
      recallLease,
      EncryptedMemorySource.authenticatedUser,
    );

    expect(recalled?.value, 'Prefers concise explanations.');
    expect(recallLease.isConsumed, isTrue);
  });

  test('model-derived candidate stays quarantined until explicit review', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = adapterFor(keys);
    final candidate = recordFor(
      keys.generation,
      source: EncryptedMemorySource.modelOutput,
      trust: EncryptedMemoryTrustTier.inferred,
      integrity: EncryptedMemoryIntegrityState.pending,
      integrityTag: null,
    );

    adapter.remember(
      lease: leaseFor(
        'remember-model',
        EncryptedMemoryOperation.remember,
        EncryptedMemorySource.modelOutput,
      ),
      safetyContext: context,
      record: candidate,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    expect(adapter.recordCount, 0);
    expect(adapter.quarantinedRecordCount, 1);
    expect(
      recall(
        adapter,
        keys,
        leaseFor(
          'recall-before-review',
          EncryptedMemoryOperation.recall,
          EncryptedMemorySource.modelOutput,
        ),
        EncryptedMemorySource.modelOutput,
      ),
      isNull,
    );

    final released = adapter.reviewQuarantined(
      lease: leaseFor(
        'review-model',
        EncryptedMemoryOperation.reviewQuarantine,
        EncryptedMemorySource.modelOutput,
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
      nowUtc: issuedAt.add(const Duration(seconds: 3)),
      disposition: EncryptedMemoryQuarantineDisposition.release,
      verifiedIntegrityTag: 'sha256:fedcba9876543210',
    );

    expect(released, isTrue);
    expect(adapter.quarantinedRecordCount, 0);
    expect(adapter.recordCount, 1);
    final recalled = recall(
      adapter,
      keys,
      leaseFor(
        'recall-after-review',
        EncryptedMemoryOperation.recall,
        EncryptedMemorySource.modelOutput,
      ),
      EncryptedMemorySource.modelOutput,
      seconds: 4,
    );
    expect(
      recalled?.provenance.trustTier,
      EncryptedMemoryTrustTier.userReviewed,
    );
    expect(recalled?.provenance.source, EncryptedMemorySource.modelOutput);
  });

  test('quarantine rejection deletes the candidate without read authority', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = adapterFor(keys);
    adapter.remember(
      lease: leaseFor(
        'remember-voice',
        EncryptedMemoryOperation.remember,
        EncryptedMemorySource.voiceInference,
      ),
      safetyContext: context,
      record: recordFor(
        keys.generation,
        source: EncryptedMemorySource.voiceInference,
        trust: EncryptedMemoryTrustTier.inferred,
        integrity: EncryptedMemoryIntegrityState.pending,
        integrityTag: null,
      ),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    expect(
      adapter.reviewQuarantined(
        lease: leaseFor(
          'reject-voice',
          EncryptedMemoryOperation.reviewQuarantine,
          EncryptedMemorySource.voiceInference,
        ),
        safetyContext: context,
        recordId: 'record-1',
        ownerId: 'owner-1',
        deviceId: 'device-1',
        capsuleId: 'personal',
        memoryClass: EncryptedMemoryClass.explicitPreference,
        source: EncryptedMemorySource.voiceInference,
        sensitivity: EncryptedMemorySensitivity.personal,
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 2)),
        disposition: EncryptedMemoryQuarantineDisposition.reject,
      ),
      isTrue,
    );
    expect(adapter.recordCount, 0);
    expect(adapter.quarantinedRecordCount, 0);
  });

  test('owner and device scopes are enforced before index access', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = adapterFor(keys);
    adapter.remember(
      lease: leaseFor(
        'remember-scope',
        EncryptedMemoryOperation.remember,
        EncryptedMemorySource.authenticatedUser,
      ),
      safetyContext: context,
      record: recordFor(keys.generation),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );
    final wrongDeviceLease = leaseFor(
      'recall-wrong-device',
      EncryptedMemoryOperation.recall,
      EncryptedMemorySource.authenticatedUser,
      deviceId: 'device-2',
    );

    expect(
      () => recall(
        adapter,
        keys,
        wrongDeviceLease,
        EncryptedMemorySource.authenticatedUser,
        deviceId: 'device-1',
      ),
      throwsA(
        isA<EncryptedMemoryPolicyViolation>().having(
          (error) => error.code,
          'code',
          'consent_not_authorized',
        ),
      ),
    );
    expect(wrongDeviceLease.isConsumed, isFalse);
  });

  test('Safe Mode and Recovery fail closed without consuming consent', () {
    var safeMode = true;
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = adapterFor(keys, safeModeReader: () => safeMode);
    final safeModeLease = leaseFor(
      'remember-safe',
      EncryptedMemoryOperation.remember,
      EncryptedMemorySource.authenticatedUser,
    );

    expect(
      () => adapter.remember(
        lease: safeModeLease,
        safetyContext: context,
        record: recordFor(keys.generation),
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      ),
      throwsA(
        isA<EncryptedMemoryPolicyViolation>().having(
          (error) => error.code,
          'code',
          'safe_mode_blocked',
        ),
      ),
    );
    expect(safeModeLease.isConsumed, isFalse);

    safeMode = false;
    final recoveryLease = leaseFor(
      'remember-recovery',
      EncryptedMemoryOperation.remember,
      EncryptedMemorySource.authenticatedUser,
    );
    expect(
      () => adapter.remember(
        lease: recoveryLease,
        safetyContext: const NeuraSafetyContext(
          directUserGesture: true,
          recoveryMode: true,
        ),
        record: recordFor(keys.generation),
        expectedKeyGeneration: keys.generation,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      ),
      throwsA(
        isA<EncryptedMemoryPolicyViolation>().having(
          (error) => error.code,
          'code',
          'recovery_mode_blocked',
        ),
      ),
    );
    expect(recoveryLease.isConsumed, isFalse);
  });

  test('stale key generations fail closed', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final firstGeneration = keys.generation;
    keys
      ..beginRotation()
      ..commitVerifiedRotation();
    final adapter = adapterFor(keys);
    final lease = leaseFor(
      'remember-stale',
      EncryptedMemoryOperation.remember,
      EncryptedMemorySource.authenticatedUser,
    );

    expect(
      () => adapter.remember(
        lease: lease,
        safetyContext: context,
        record: recordFor(firstGeneration),
        expectedKeyGeneration: firstGeneration,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      ),
      throwsA(isA<EncryptedMemoryPolicyViolation>()),
    );
    expect(lease.isConsumed, isFalse);
  });

  test('suspend clears admitted and quarantined records', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = adapterFor(keys);
    adapter.remember(
      lease: leaseFor(
        'remember-clear',
        EncryptedMemoryOperation.remember,
        EncryptedMemorySource.modelOutput,
      ),
      safetyContext: context,
      record: recordFor(
        keys.generation,
        source: EncryptedMemorySource.modelOutput,
        trust: EncryptedMemoryTrustTier.inferred,
        integrity: EncryptedMemoryIntegrityState.pending,
        integrityTag: null,
      ),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    adapter.suspendAndClear();
    expect(adapter.isSuspended, isTrue);
    expect(adapter.recordCount, 0);
    expect(adapter.quarantinedRecordCount, 0);

    adapter.resumeEmptySession();
    expect(adapter.isSuspended, isFalse);
    expect(adapter.recordCount, 0);
  });

  test('recall consumes consent even when no record matches', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = adapterFor(keys);
    final lease = leaseFor(
      'recall-missing',
      EncryptedMemoryOperation.recall,
      EncryptedMemorySource.authenticatedUser,
    );

    final result = recall(
      adapter,
      keys,
      lease,
      EncryptedMemorySource.authenticatedUser,
      recordId: 'missing',
    );

    expect(result, isNull);
    expect(lease.isConsumed, isTrue);
  });
}
