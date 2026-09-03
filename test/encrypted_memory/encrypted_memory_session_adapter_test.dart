import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_session_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 9, 2, 12);

  EncryptedMemoryConsentLease leaseFor(
    String id,
    EncryptedMemoryOperation operation,
  ) {
    return EncryptedMemoryConsentLease(
      id: id,
      capsuleId: 'personal',
      operations: {operation},
      classes: const {EncryptedMemoryClass.explicitPreference},
      issuedAtUtc: issuedAt,
      expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
      directUserGesture: true,
    );
  }

  EncryptedMemorySessionRecord recordFor(int generation) {
    return EncryptedMemorySessionRecord(
      id: 'record-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      value: 'Prefers concise explanations.',
      createdAtUtc: issuedAt,
      keyGeneration: generation,
    );
  }

  test('explicit remember and recall use separate single-use leases', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = EncryptedMemorySessionAdapter(
      safetyPolicy: NeuraLivingSafetyPolicy(safeModeReader: () => false),
      keyLifecycle: keys,
    );
    const context = NeuraSafetyContext(directUserGesture: true);
    final rememberLease = leaseFor(
      'remember-1',
      EncryptedMemoryOperation.remember,
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

    final recallLease = leaseFor('recall-1', EncryptedMemoryOperation.recall);
    final recalled = adapter.recall(
      lease: recallLease,
      safetyContext: context,
      recordId: 'record-1',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 2)),
    );

    expect(recalled?.value, 'Prefers concise explanations.');
    expect(recallLease.isConsumed, isTrue);
  });

  test('Safe Mode and Recovery fail closed without consuming consent', () {
    var safeMode = true;
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = EncryptedMemorySessionAdapter(
      safetyPolicy: NeuraLivingSafetyPolicy(
        safeModeReader: () => safeMode,
      ),
      keyLifecycle: keys,
    );
    final safeModeLease = leaseFor(
      'remember-safe',
      EncryptedMemoryOperation.remember,
    );

    expect(
      () => adapter.remember(
        lease: safeModeLease,
        safetyContext: const NeuraSafetyContext(directUserGesture: true),
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
    final adapter = EncryptedMemorySessionAdapter(
      safetyPolicy: NeuraLivingSafetyPolicy(safeModeReader: () => false),
      keyLifecycle: keys,
    );
    final lease = leaseFor('remember-stale', EncryptedMemoryOperation.remember);

    expect(
      () => adapter.remember(
        lease: lease,
        safetyContext: const NeuraSafetyContext(directUserGesture: true),
        record: recordFor(firstGeneration),
        expectedKeyGeneration: firstGeneration,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      ),
      throwsA(isA<EncryptedMemoryPolicyViolation>()),
    );
    expect(lease.isConsumed, isFalse);
  });

  test('suspend clears records and resume starts empty', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = EncryptedMemorySessionAdapter(
      safetyPolicy: NeuraLivingSafetyPolicy(safeModeReader: () => false),
      keyLifecycle: keys,
    );
    adapter.remember(
      lease: leaseFor('remember-clear', EncryptedMemoryOperation.remember),
      safetyContext: const NeuraSafetyContext(directUserGesture: true),
      record: recordFor(keys.generation),
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    adapter.suspendAndClear();
    expect(adapter.isSuspended, isTrue);
    expect(adapter.recordCount, 0);

    adapter.resumeEmptySession();
    expect(adapter.isSuspended, isFalse);
    expect(adapter.recordCount, 0);
  });

  test('recall consumes consent even when no record matches', () {
    final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    final adapter = EncryptedMemorySessionAdapter(
      safetyPolicy: NeuraLivingSafetyPolicy(safeModeReader: () => false),
      keyLifecycle: keys,
    );
    final lease = leaseFor('recall-missing', EncryptedMemoryOperation.recall);

    final result = adapter.recall(
      lease: lease,
      safetyContext: const NeuraSafetyContext(directUserGesture: true),
      recordId: 'missing',
      capsuleId: 'personal',
      memoryClass: EncryptedMemoryClass.explicitPreference,
      expectedKeyGeneration: keys.generation,
      nowUtc: issuedAt.add(const Duration(seconds: 1)),
    );

    expect(result, isNull);
    expect(lease.isConsumed, isTrue);
  });
}
