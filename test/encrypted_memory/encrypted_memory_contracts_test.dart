import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 8, 30, 17);

  group('encrypted memory consent', () {
    test('is exact-scope, short-lived, direct, and single-use', () {
      final lease = EncryptedMemoryConsentLease(
        id: 'lease-1',
        capsuleId: 'personal',
        operations: const {EncryptedMemoryOperation.remember},
        classes: const {EncryptedMemoryClass.explicitPreference},
        issuedAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
        directUserGesture: true,
      );

      expect(
        lease.authorizes(
          requestedCapsuleId: 'personal',
          operation: EncryptedMemoryOperation.remember,
          memoryClass: EncryptedMemoryClass.explicitPreference,
          nowUtc: issuedAt.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        lease.authorizes(
          requestedCapsuleId: 'work',
          operation: EncryptedMemoryOperation.remember,
          memoryClass: EncryptedMemoryClass.explicitPreference,
          nowUtc: issuedAt.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );

      lease.consumeFor(
        requestedCapsuleId: 'personal',
        operation: EncryptedMemoryOperation.remember,
        memoryClass: EncryptedMemoryClass.explicitPreference,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      );
      expect(lease.isConsumed, isTrue);
      expect(
        lease.authorizes(
          requestedCapsuleId: 'personal',
          operation: EncryptedMemoryOperation.remember,
          memoryClass: EncryptedMemoryClass.explicitPreference,
          nowUtc: issuedAt.add(const Duration(seconds: 2)),
        ),
        isFalse,
      );
    });

    test('rejects long-lived or non-direct authority', () {
      expect(
        () => EncryptedMemoryConsentLease(
          id: 'lease-2',
          capsuleId: 'personal',
          operations: const {EncryptedMemoryOperation.recall},
          classes: const {EncryptedMemoryClass.boundedContinuityFact},
          issuedAtUtc: issuedAt,
          expiresAtUtc: issuedAt.add(const Duration(hours: 1)),
          directUserGesture: true,
        ),
        throwsA(isA<EncryptedMemoryPolicyViolation>()),
      );

      final indirect = EncryptedMemoryConsentLease(
        id: 'lease-3',
        capsuleId: 'personal',
        operations: const {EncryptedMemoryOperation.recall},
        classes: const {EncryptedMemoryClass.boundedContinuityFact},
        issuedAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
        directUserGesture: false,
      );
      expect(
        indirect.authorizes(
          requestedCapsuleId: 'personal',
          operation: EncryptedMemoryOperation.recall,
          memoryClass: EncryptedMemoryClass.boundedContinuityFact,
          nowUtc: issuedAt.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });
  });

  group('key lifecycle', () {
    test('fails closed across rotation, suspension, and destruction', () {
      final keys = EncryptedMemoryKeyLifecycle();
      keys.provisionVerifiedKey();
      final firstGeneration = keys.generation;
      keys.requireUsableGeneration(firstGeneration);

      keys.beginRotation();
      expect(
        () => keys.requireUsableGeneration(firstGeneration),
        throwsA(isA<EncryptedMemoryPolicyViolation>()),
      );
      keys.commitVerifiedRotation();
      expect(keys.generation, firstGeneration + 1);

      keys.suspend();
      expect(
        () => keys.requireUsableGeneration(keys.generation),
        throwsA(isA<EncryptedMemoryPolicyViolation>()),
      );
      keys.destroyVerifiedKey();
      expect(keys.state, EncryptedMemoryKeyState.destroyed);
      expect(
        keys.provisionVerifiedKey,
        throwsA(isA<EncryptedMemoryPolicyViolation>()),
      );
    });
  });

  group('export and wipe', () {
    test('export is bounded to selected records and destination', () {
      final export = EncryptedMemoryExportContract(
        capsuleId: 'personal',
        recordIds: const {'record-1', 'record-2'},
        createdAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
        userSelectedDestination: true,
      );
      expect(
        export.permitsRecord(
          'record-1',
          issuedAt.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        export.permitsRecord(
          'record-3',
          issuedAt.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test(
      'wipe requires shutdown, deletion, key destruction, and verification',
      () {
        const complete = EncryptedMemoryWipeContract(
          stopWritersFirst: true,
          deleteCiphertext: true,
          destroyKey: true,
          verifyCiphertextDeletion: true,
          verifyKeyDeletion: true,
        );
        expect(complete.validate, returnsNormally);

        const incomplete = EncryptedMemoryWipeContract(
          stopWritersFirst: true,
          deleteCiphertext: true,
          destroyKey: true,
          verifyCiphertextDeletion: false,
          verifyKeyDeletion: true,
        );
        expect(
          incomplete.validate,
          throwsA(isA<EncryptedMemoryPolicyViolation>()),
        );
      },
    );
  });
}
