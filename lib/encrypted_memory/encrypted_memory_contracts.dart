/// Policy-only foundation for Neura's future encrypted memory runtime.
///
/// Nothing in this library performs I/O, encryption, background capture,
/// inference, or execution. Runtime integration remains intentionally absent.
library;

enum EncryptedMemoryOperation { remember, recall, export, wipe }

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

enum EncryptedMemoryKeyState {
  absent,
  active,
  rotating,
  suspended,
  destroyed,
}

final class EncryptedMemoryPolicyViolation implements Exception {
  const EncryptedMemoryPolicyViolation(this.code);

  final String code;

  @override
  String toString() => 'EncryptedMemoryPolicyViolation($code)';
}

final class EncryptedMemoryConsentLease {
  EncryptedMemoryConsentLease({
    required this.id,
    required this.capsuleId,
    required Set<EncryptedMemoryOperation> operations,
    required Set<EncryptedMemoryClass> classes,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    required this.directUserGesture,
  })  : operations = Set.unmodifiable(operations),
        classes = Set.unmodifiable(classes) {
    _requireBoundedId(id, 'lease_id');
    _requireBoundedId(capsuleId, 'capsule_id');
    if (this.operations.isEmpty) {
      throw const EncryptedMemoryPolicyViolation('empty_operations');
    }
    if (this.classes.isEmpty) {
      throw const EncryptedMemoryPolicyViolation('empty_classes');
    }
    if (!expiresAtUtc.isAfter(issuedAtUtc)) {
      throw const EncryptedMemoryPolicyViolation('invalid_expiry');
    }
    if (expiresAtUtc.difference(issuedAtUtc) > const Duration(minutes: 15)) {
      throw const EncryptedMemoryPolicyViolation('lease_too_long');
    }
  }

  final String id;
  final String capsuleId;
  final Set<EncryptedMemoryOperation> operations;
  final Set<EncryptedMemoryClass> classes;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final bool directUserGesture;
  bool _consumed = false;

  bool authorizes({
    required String requestedCapsuleId,
    required EncryptedMemoryOperation operation,
    required EncryptedMemoryClass memoryClass,
    required DateTime nowUtc,
  }) {
    if (_consumed ||
        !directUserGesture ||
        requestedCapsuleId != capsuleId ||
        nowUtc.isBefore(issuedAtUtc) ||
        !nowUtc.isBefore(expiresAtUtc)) {
      return false;
    }
    return operations.contains(operation) && classes.contains(memoryClass);
  }

  void consumeFor({
    required String requestedCapsuleId,
    required EncryptedMemoryOperation operation,
    required EncryptedMemoryClass memoryClass,
    required DateTime nowUtc,
  }) {
    if (!authorizes(
      requestedCapsuleId: requestedCapsuleId,
      operation: operation,
      memoryClass: memoryClass,
      nowUtc: nowUtc,
    )) {
      throw const EncryptedMemoryPolicyViolation('consent_not_authorized');
    }
    _consumed = true;
  }

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
    if (!expiresAtUtc.isAfter(createdAtUtc) ||
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
}

void _requireBoundedId(String value, String code) {
  if (value.isEmpty ||
      value.length > 256 ||
      value.trim() != value ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw EncryptedMemoryPolicyViolation(code);
  }
}
