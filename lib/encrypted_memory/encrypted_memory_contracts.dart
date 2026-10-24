/// Policy-only foundation for Neura's encrypted memory runtime.
///
/// Nothing in this library performs I/O, encryption, background capture,
/// inference, or execution. Every runtime must preserve these fail-closed
/// scope, consent, provenance, and lifecycle contracts.
library;

enum EncryptedMemoryOperation {
  remember,
  recall,
  correct,
  forget,
  reviewQuarantine,
  export,
  wipe,
}

/// The only record classes admitted by the MVP contract.
///
/// Raw conversations, messages, journals, therapy content, dreams, mood notes,
/// goals, plan copy, quest titles, credentials, biometrics, and device details
/// have no representable class and therefore fail closed.
enum EncryptedMemoryClass {
  userAuthoredNote,
  explicitPreference,
  boundedContinuityFact,
  userApprovedDerivedLabel,
}

/// Where a candidate memory originated. The source is immutable provenance,
/// not an assertion that the content is trustworthy.
enum EncryptedMemorySource {
  authenticatedUser,
  localDocument,
  externalDocument,
  webContent,
  modelOutput,
  voiceInference,
}

/// Trust is assigned by deterministic policy and explicit review. Model output
/// and voice inference can never grant themselves a higher tier.
enum EncryptedMemoryTrustTier {
  unverified,
  inferred,
  verifiedImport,
  authenticatedUser,
  userReviewed,
}

enum EncryptedMemoryIntegrityState { pending, verified, failed }

enum EncryptedMemorySensitivity { standard, personal, sensitive }

enum EncryptedMemoryKeyState { absent, active, rotating, suspended, destroyed }

final class EncryptedMemoryPolicyViolation implements Exception {
  const EncryptedMemoryPolicyViolation(this.code);

  final String code;

  @override
  String toString() => 'EncryptedMemoryPolicyViolation($code)';
}

/// Exact retrieval scope enforced before the memory index can return content.
///
/// Owner, device, capsule, source, class, and sensitivity are all part of the
/// lookup key. A caller cannot retrieve a broader set and filter it later.
final class EncryptedMemoryAccessScope {
  EncryptedMemoryAccessScope({
    required this.ownerId,
    required this.deviceId,
    required this.capsuleId,
    required Set<EncryptedMemoryClass> classes,
    required Set<EncryptedMemorySource> sources,
    required this.sensitivity,
  })  : classes = Set.unmodifiable(classes),
        sources = Set.unmodifiable(sources) {
    _requireBoundedId(ownerId, 'owner_id');
    _requireBoundedId(deviceId, 'device_id');
    _requireBoundedId(capsuleId, 'capsule_id');
    if (this.classes.length != 1) {
      throw const EncryptedMemoryPolicyViolation('non_exact_classes');
    }
    if (this.sources.length != 1) {
      throw const EncryptedMemoryPolicyViolation('non_exact_sources');
    }
  }

  final String ownerId;
  final String deviceId;
  final String capsuleId;
  final Set<EncryptedMemoryClass> classes;
  final Set<EncryptedMemorySource> sources;
  final EncryptedMemorySensitivity sensitivity;

  bool permits({
    required String requestedOwnerId,
    required String requestedDeviceId,
    required String requestedCapsuleId,
    required EncryptedMemoryClass memoryClass,
    required EncryptedMemorySource source,
    required EncryptedMemorySensitivity sensitivity,
  }) {
    return requestedOwnerId == ownerId &&
        requestedDeviceId == deviceId &&
        requestedCapsuleId == capsuleId &&
        classes.contains(memoryClass) &&
        sources.contains(source) &&
        sensitivity == this.sensitivity;
  }
}

/// Immutable origin and integrity metadata carried beside memory content.
///
/// [reason] is a bounded, non-secret policy reason such as
/// "user_tapped_remember"; it must not contain copied prompt or journal text.
final class EncryptedMemoryProvenance {
  EncryptedMemoryProvenance({
    required this.source,
    required this.sourceId,
    required this.authorId,
    required this.reason,
    required this.trustTier,
    required this.integrityState,
    required this.integrityTag,
    required this.observedAtUtc,
    this.reviewedAtUtc,
  }) {
    _requireBoundedId(sourceId, 'source_id');
    _requireBoundedId(authorId, 'author_id');
    _requireBoundedId(reason, 'provenance_reason');
    if (!observedAtUtc.isUtc ||
        (reviewedAtUtc != null && !reviewedAtUtc!.isUtc)) {
      throw const EncryptedMemoryPolicyViolation('provenance_time_not_utc');
    }
    if (reviewedAtUtc != null && reviewedAtUtc!.isBefore(observedAtUtc)) {
      throw const EncryptedMemoryPolicyViolation('review_precedes_observation');
    }
    if (integrityState == EncryptedMemoryIntegrityState.verified) {
      _requireIntegrityTag(integrityTag);
    } else if (integrityTag != null && integrityTag!.isNotEmpty) {
      _requireIntegrityTag(integrityTag);
    }
    if (trustTier == EncryptedMemoryTrustTier.userReviewed &&
        reviewedAtUtc == null) {
      throw const EncryptedMemoryPolicyViolation(
        'reviewed_trust_without_review',
      );
    }
  }

  final EncryptedMemorySource source;
  final String sourceId;
  final String authorId;
  final String reason;
  final EncryptedMemoryTrustTier trustTier;
  final EncryptedMemoryIntegrityState integrityState;
  final String? integrityTag;
  final DateTime observedAtUtc;
  final DateTime? reviewedAtUtc;

  bool get requiresQuarantine {
    if (integrityState != EncryptedMemoryIntegrityState.verified) return true;
    if (trustTier == EncryptedMemoryTrustTier.unverified ||
        trustTier == EncryptedMemoryTrustTier.inferred) {
      return true;
    }
    if (source == EncryptedMemorySource.modelOutput ||
        source == EncryptedMemorySource.voiceInference ||
        source == EncryptedMemorySource.webContent) {
      return trustTier != EncryptedMemoryTrustTier.userReviewed;
    }
    return false;
  }

  EncryptedMemoryProvenance reviewed({
    required DateTime reviewedAtUtc,
    required String verifiedIntegrityTag,
  }) {
    return EncryptedMemoryProvenance(
      source: source,
      sourceId: sourceId,
      authorId: authorId,
      reason: reason,
      trustTier: EncryptedMemoryTrustTier.userReviewed,
      integrityState: EncryptedMemoryIntegrityState.verified,
      integrityTag: verifiedIntegrityTag,
      observedAtUtc: observedAtUtc,
      reviewedAtUtc: reviewedAtUtc,
    );
  }
}

final class EncryptedMemoryConsentLease {
  EncryptedMemoryConsentLease({
    required this.id,
    required this.scope,
    required Set<EncryptedMemoryOperation> operations,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    required this.directUserGesture,
  }) : operations = Set.unmodifiable(operations) {
    _requireBoundedId(id, 'lease_id');
    if (this.operations.isEmpty) {
      throw const EncryptedMemoryPolicyViolation('empty_operations');
    }
    if (!issuedAtUtc.isUtc || !expiresAtUtc.isUtc) {
      throw const EncryptedMemoryPolicyViolation('lease_time_not_utc');
    }
    if (!expiresAtUtc.isAfter(issuedAtUtc)) {
      throw const EncryptedMemoryPolicyViolation('invalid_expiry');
    }
    if (expiresAtUtc.difference(issuedAtUtc) > const Duration(minutes: 15)) {
      throw const EncryptedMemoryPolicyViolation('lease_too_long');
    }
  }

  final String id;
  final EncryptedMemoryAccessScope scope;
  final Set<EncryptedMemoryOperation> operations;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final bool directUserGesture;
  bool _consumed = false;
  bool _revoked = false;

  /// Revocation also invalidates an operation already waiting on native I/O.
  void revoke() => _revoked = true;

  bool get isRevoked => _revoked;

  bool authorizes({
    required EncryptedMemoryOperation operation,
    required String requestedOwnerId,
    required String requestedDeviceId,
    required String requestedCapsuleId,
    required EncryptedMemoryClass memoryClass,
    required EncryptedMemorySource source,
    required EncryptedMemorySensitivity sensitivity,
    required DateTime nowUtc,
  }) {
    if (_consumed ||
        !directUserGesture ||
        !isWithinLifetime(nowUtc) ||
        !operations.contains(operation)) {
      return false;
    }
    return scope.permits(
      requestedOwnerId: requestedOwnerId,
      requestedDeviceId: requestedDeviceId,
      requestedCapsuleId: requestedCapsuleId,
      memoryClass: memoryClass,
      source: source,
      sensitivity: sensitivity,
    );
  }

  void consumeFor({
    required EncryptedMemoryOperation operation,
    required String requestedOwnerId,
    required String requestedDeviceId,
    required String requestedCapsuleId,
    required EncryptedMemoryClass memoryClass,
    required EncryptedMemorySource source,
    required EncryptedMemorySensitivity sensitivity,
    required DateTime nowUtc,
  }) {
    if (!authorizes(
      operation: operation,
      requestedOwnerId: requestedOwnerId,
      requestedDeviceId: requestedDeviceId,
      requestedCapsuleId: requestedCapsuleId,
      memoryClass: memoryClass,
      source: source,
      sensitivity: sensitivity,
      nowUtc: nowUtc,
    )) {
      throw const EncryptedMemoryPolicyViolation('consent_not_authorized');
    }
    _consumed = true;
  }

  /// Lifetime validation remains meaningful after the one permitted use.
  /// Async adapters recheck it before publishing or committing that operation.
  bool isWithinLifetime(DateTime nowUtc) =>
      !_revoked &&
      nowUtc.isUtc &&
      !nowUtc.isBefore(issuedAtUtc) &&
      nowUtc.isBefore(expiresAtUtc);

  bool get isConsumed => _consumed;
}

final class EncryptedMemoryKeyLifecycle {
  EncryptedMemoryKeyState _state = EncryptedMemoryKeyState.absent;
  int _generation = 0;

  EncryptedMemoryKeyState get state => _state;
  int get generation => _generation;

  void provisionVerifiedKey() {
    if (_state != EncryptedMemoryKeyState.absent) {
      throw const EncryptedMemoryPolicyViolation('key_already_initialized');
    }
    _generation++;
    _state = EncryptedMemoryKeyState.active;
  }

  void beginRotation() {
    if (_state != EncryptedMemoryKeyState.active) {
      throw const EncryptedMemoryPolicyViolation('rotation_not_allowed');
    }
    _state = EncryptedMemoryKeyState.rotating;
  }

  void commitVerifiedRotation() {
    if (_state != EncryptedMemoryKeyState.rotating) {
      throw const EncryptedMemoryPolicyViolation('rotation_not_started');
    }
    _generation++;
    _state = EncryptedMemoryKeyState.active;
  }

  void suspend() {
    if (_state != EncryptedMemoryKeyState.active &&
        _state != EncryptedMemoryKeyState.rotating) {
      throw const EncryptedMemoryPolicyViolation('suspend_not_allowed');
    }
    _state = EncryptedMemoryKeyState.suspended;
  }

  void destroyVerifiedKey() {
    if (_state == EncryptedMemoryKeyState.destroyed) {
      throw const EncryptedMemoryPolicyViolation('key_already_destroyed');
    }
    _generation++;
    _state = EncryptedMemoryKeyState.destroyed;
  }

  void requireUsableGeneration(int expectedGeneration) {
    if (_state != EncryptedMemoryKeyState.active ||
        expectedGeneration != _generation) {
      throw const EncryptedMemoryPolicyViolation('key_not_usable');
    }
  }
}

final class EncryptedMemoryExportContract {
  EncryptedMemoryExportContract({
    required this.capsuleId,
    required Set<String> recordIds,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    required this.userSelectedDestination,
  }) : recordIds = Set.unmodifiable(recordIds) {
    _requireBoundedId(capsuleId, 'capsule_id');
    if (this.recordIds.isEmpty || this.recordIds.length > 1000) {
      throw const EncryptedMemoryPolicyViolation('invalid_export_scope');
    }
    for (final id in this.recordIds) {
      _requireBoundedId(id, 'record_id');
    }
    if (!userSelectedDestination) {
      throw const EncryptedMemoryPolicyViolation(
        'export_destination_not_user_selected',
      );
    }
    if (!createdAtUtc.isUtc ||
        !expiresAtUtc.isUtc ||
        !expiresAtUtc.isAfter(createdAtUtc) ||
        expiresAtUtc.difference(createdAtUtc) > const Duration(minutes: 15)) {
      throw const EncryptedMemoryPolicyViolation('invalid_export_expiry');
    }
  }

  final String capsuleId;
  final Set<String> recordIds;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final bool userSelectedDestination;

  bool permitsRecord(String recordId, DateTime nowUtc) =>
      nowUtc.isUtc &&
      !nowUtc.isBefore(createdAtUtc) &&
      nowUtc.isBefore(expiresAtUtc) &&
      recordIds.contains(recordId);
}

final class EncryptedMemoryWipeContract {
  const EncryptedMemoryWipeContract({
    required this.stopWritersFirst,
    required this.deleteCiphertext,
    required this.destroyKey,
    required this.verifyCiphertextDeletion,
    required this.verifyKeyDeletion,
  });

  final bool stopWritersFirst;
  final bool deleteCiphertext;
  final bool destroyKey;
  final bool verifyCiphertextDeletion;
  final bool verifyKeyDeletion;

  void validate() {
    if (!stopWritersFirst ||
        !deleteCiphertext ||
        !destroyKey ||
        !verifyCiphertextDeletion ||
        !verifyKeyDeletion) {
      throw const EncryptedMemoryPolicyViolation('incomplete_wipe_contract');
    }
  }

  void validateScopedCiphertextOnly() {
    if (!stopWritersFirst || !deleteCiphertext || !verifyCiphertextDeletion) {
      throw const EncryptedMemoryPolicyViolation('incomplete_wipe_contract');
    }
    if (destroyKey || verifyKeyDeletion) {
      throw const EncryptedMemoryPolicyViolation(
        'scoped_wipe_cannot_destroy_shared_key',
      );
    }
  }
}

void _requireBoundedId(String value, String code) {
  if (value.isEmpty ||
      value.length > 256 ||
      value.trim() != value ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw EncryptedMemoryPolicyViolation(code);
  }
}

void _requireIntegrityTag(String? value) {
  if (value == null ||
      value.length < 16 ||
      value.length > 256 ||
      value.trim() != value ||
      value.codeUnits.any((unit) => unit < 0x21 || unit == 0x7f)) {
    throw const EncryptedMemoryPolicyViolation('invalid_integrity_tag');
  }
}
