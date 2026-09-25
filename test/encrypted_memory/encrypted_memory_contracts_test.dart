import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 9, 25, 12);
  final scope = EncryptedMemoryAccessScope(
    ownerId: 'owner-1',
    deviceId: 'device-1',
    capsuleId: 'personal',
    classes: const {EncryptedMemoryClass.explicitPreference},
    sources: const {
      EncryptedMemorySource.authenticatedUser,
      EncryptedMemorySource.modelOutput,
    },
    sensitivity: EncryptedMemorySensitivity.personal,
  );

  group('encrypted memory consent and retrieval scope', () {
    test('is exact-scope, short-lived, direct, and single-use', () {
      final lease = EncryptedMemoryConsentLease(
        id: 'lease-1',
        scope: scope,
        operations: const {EncryptedMemoryOperation.remember},
        issuedAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
        directUserGesture: true,
      );

      expect(
        lease.authorizes(
          operation: EncryptedMemoryOperation.remember,
          requestedOwnerId: 'owner-1',
          requestedDeviceId: 'device-1',
          requestedCapsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          source: EncryptedMemorySource.authenticatedUser,
          sensitivity: EncryptedMemorySensitivity.personal,
          nowUtc: issuedAt.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        lease.authorizes(
          operation: EncryptedMemoryOperation.remember,
          requestedOwnerId: 'owner-1',
          requestedDeviceId: 'device-2',
          requestedCapsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          source: EncryptedMemorySource.authenticatedUser,
          sensitivity: EncryptedMemorySensitivity.personal,
          nowUtc: issuedAt.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        lease.authorizes(
          operation: EncryptedMemoryOperation.remember,
          requestedOwnerId: 'owner-1',
          requestedDeviceId: 'device-1',
          requestedCapsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          source: EncryptedMemorySource.authenticatedUser,
          sensitivity: EncryptedMemorySensitivity.standard,
          nowUtc: issuedAt.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        lease.authorizes(
          operation: EncryptedMemoryOperation.remember,
          requestedOwnerId: 'owner-1',
          requestedDeviceId: 'device-1',
          requestedCapsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          source: EncryptedMemorySource.authenticatedUser,
          sensitivity: EncryptedMemorySensitivity.sensitive,
          nowUtc: issuedAt.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );

      lease.consumeFor(
        operation: EncryptedMemoryOperation.remember,
        requestedOwnerId: 'owner-1',
        requestedDeviceId: 'device-1',
        requestedCapsuleId: 'personal',
        memoryClass: EncryptedMemoryClass.explicitPreference,
        source: EncryptedMemorySource.authenticatedUser,
        sensitivity: EncryptedMemorySensitivity.personal,
        nowUtc: issuedAt.add(const Duration(seconds: 1)),
      );
      expect(lease.isConsumed, isTrue);
      expect(
        lease.authorizes(
          operation: EncryptedMemoryOperation.remember,
          requestedOwnerId: 'owner-1',
          requestedDeviceId: 'device-1',
          requestedCapsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          source: EncryptedMemorySource.authenticatedUser,
          sensitivity: EncryptedMemorySensitivity.personal,
          nowUtc: issuedAt.add(const Duration(seconds: 2)),
        ),
        isFalse,
      );
    });

    test('rejects long-lived and non-direct authority', () {
      expect(
        () => EncryptedMemoryConsentLease(
          id: 'lease-2',
          scope: scope,
          operations: const {EncryptedMemoryOperation.recall},
          issuedAtUtc: issuedAt,
          expiresAtUtc: issuedAt.add(const Duration(hours: 1)),
          directUserGesture: true,
        ),
        throwsA(isA<EncryptedMemoryPolicyViolation>()),
      );

      final indirect = EncryptedMemoryConsentLease(
        id: 'lease-3',
        scope: scope,
        operations: const {EncryptedMemoryOperation.recall},
        issuedAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
        directUserGesture: false,
      );
      expect(
        indirect.authorizes(
          operation: EncryptedMemoryOperation.recall,
          requestedOwnerId: 'owner-1',
          requestedDeviceId: 'device-1',
          requestedCapsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          source: EncryptedMemorySource.authenticatedUser,
          sensitivity: EncryptedMemorySensitivity.personal,
          nowUtc: issuedAt.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });
  });

  group('provenance admission', () {
    test('model output and voice inference require user review', () {
      for (final source in const [
        EncryptedMemorySource.modelOutput,
        EncryptedMemorySource.voiceInference,
      ]) {
        final provenance = EncryptedMemoryProvenance(
          source: source,
          sourceId: 'turn-1',
          authorId: 'local-model',
          reason: 'candidate_memory',
          trustTier: EncryptedMemoryTrustTier.inferred,
          integrityState: EncryptedMemoryIntegrityState.pending,
          integrityTag: null,
          observedAtUtc: issuedAt,
        );
        expect(provenance.requiresQuarantine, isTrue);

        final reviewed = provenance.reviewed(
          reviewedAtUtc: issuedAt.add(const Duration(seconds: 10)),
          verifiedIntegrityTag: 'sha256:0123456789abcdef',
        );
        expect(reviewed.requiresQuarantine, isFalse);
        expect(reviewed.source, source);
        expect(reviewed.trustTier, EncryptedMemoryTrustTier.userReviewed);
      }
    });

    test('verified authenticated input is admitted without quarantine', () {
      final provenance = EncryptedMemoryProvenance(
        source: EncryptedMemorySource.authenticatedUser,
        sourceId: 'gesture-1',
        authorId: 'owner-1',
        reason: 'user_tapped_remember',
        trustTier: EncryptedMemoryTrustTier.authenticatedUser,
        integrityState: EncryptedMemoryIntegrityState.verified,
        integrityTag: 'sha256:0123456789abcdef',
        observedAtUtc: issuedAt,
      );

      expect(provenance.requiresQuarantine, isFalse);
    });

    test('reviewed trust requires a review timestamp', () {
      expect(
        () => EncryptedMemoryProvenance(
          source: EncryptedMemorySource.webContent,
          sourceId: 'page-1',
          authorId: 'importer',
          reason: 'explicit_import',
          trustTier: EncryptedMemoryTrustTier.userReviewed,
          integrityState: EncryptedMemoryIntegrityState.verified,
          integrityTag: 'sha256:0123456789abcdef',
          observedAtUtc: issuedAt,
        ),
        throwsA(isA<EncryptedMemoryPolicyViolation>()),
      );
    });

    test('review evidence cannot predate the observed source', () {
      expect(
        () => EncryptedMemoryProvenance(
          source: EncryptedMemorySource.webContent,
          sourceId: 'page-1',
          authorId: 'reviewer-1',
          reason: 'explicit_import',
          trustTier: EncryptedMemoryTrustTier.userReviewed,
          integrityState: EncryptedMemoryIntegrityState.verified,
          integrityTag: 'sha256:0123456789abcdef',
          observedAtUtc: issuedAt,
          reviewedAtUtc: issuedAt.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<EncryptedMemoryPolicyViolation>()),
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
