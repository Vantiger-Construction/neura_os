import '../living_intelligence/neura_safety_policy.dart';
import 'encrypted_memory_contracts.dart';

/// One explicitly remembered value retained only for this process lifetime.
///
/// The adapter deliberately has no serialization surface. Records disappear
/// when [EncryptedMemorySessionAdapter.clearSession] is called or the process
/// exits.
final class EncryptedMemorySessionRecord {
  EncryptedMemorySessionRecord({
    required this.id,
    required this.ownerId,
    required this.deviceId,
    required this.capsuleId,
    required this.memoryClass,
    required this.sensitivity,
    required this.provenance,
    required this.value,
    required this.createdAtUtc,
    required this.keyGeneration,
  }) {
    _requireSessionId(id, 'record_id');
    _requireSessionId(ownerId, 'owner_id');
    _requireSessionId(deviceId, 'device_id');
    _requireSessionId(capsuleId, 'capsule_id');
    if (value.isEmpty || value.length > 4096 || _hasControlCharacter(value)) {
      throw const EncryptedMemoryPolicyViolation('invalid_record_value');
    }
    if (!createdAtUtc.isUtc) {
      throw const EncryptedMemoryPolicyViolation('record_time_not_utc');
    }
    if (keyGeneration <= 0) {
      throw const EncryptedMemoryPolicyViolation('invalid_key_generation');
    }
  }

  final String id;
  final String ownerId;
  final String deviceId;
  final String capsuleId;
  final EncryptedMemoryClass memoryClass;
  final EncryptedMemorySensitivity sensitivity;
  final EncryptedMemoryProvenance provenance;
  final String value;
  final DateTime createdAtUtc;
  final int keyGeneration;

  EncryptedMemorySessionRecord reviewed({
    required DateTime reviewedAtUtc,
    required String verifiedIntegrityTag,
  }) {
    return EncryptedMemorySessionRecord(
      id: id,
      ownerId: ownerId,
      deviceId: deviceId,
      capsuleId: capsuleId,
      memoryClass: memoryClass,
      sensitivity: sensitivity,
      provenance: provenance.reviewed(
        reviewedAtUtc: reviewedAtUtc,
        verifiedIntegrityTag: verifiedIntegrityTag,
      ),
      value: value,
      createdAtUtc: createdAtUtc,
      keyGeneration: keyGeneration,
    );
  }

  bool matchesScope({
    required String requestedOwnerId,
    required String requestedDeviceId,
    required String requestedCapsuleId,
    required EncryptedMemoryClass requestedClass,
    required EncryptedMemorySource requestedSource,
    required EncryptedMemorySensitivity requestedSensitivity,
    required int expectedKeyGeneration,
  }) {
    return ownerId == requestedOwnerId &&
        deviceId == requestedDeviceId &&
        capsuleId == requestedCapsuleId &&
        memoryClass == requestedClass &&
        provenance.source == requestedSource &&
        sensitivity == requestedSensitivity &&
        keyGeneration == expectedKeyGeneration;
  }
}

enum EncryptedMemoryQuarantineDisposition { release, reject }

/// Consent-gated, process-local encrypted-memory runtime seam.
///
/// This adapter provides explicit remember, quarantine review, and exact-scope
/// recall only. It performs no filesystem or database writes, encryption,
/// export, wipe, migration, background capture, inference, device sync, or
/// Action Loom operation. An already verified key lifecycle is still required
/// as a generation-bound access gate so a later durable adapter cannot bypass
/// the foundation.
final class EncryptedMemorySessionAdapter {
  EncryptedMemorySessionAdapter({
    required this.safetyPolicy,
    required this.keyLifecycle,
  });

  final NeuraLivingSafetyPolicy safetyPolicy;
  final EncryptedMemoryKeyLifecycle keyLifecycle;
  final Map<String, EncryptedMemorySessionRecord> _records = {};
  final Map<String, EncryptedMemorySessionRecord> _quarantine = {};

  bool _suspended = false;

  int get recordCount => _records.length;
  int get quarantinedRecordCount => _quarantine.length;
  bool get isSuspended => _suspended;

  void remember({
    required EncryptedMemoryConsentLease lease,
    required NeuraSafetyContext safetyContext,
    required EncryptedMemorySessionRecord record,
    required int expectedKeyGeneration,
    required DateTime nowUtc,
  }) {
    _requireAvailable(safetyContext, expectedKeyGeneration);
    _requireUtc(nowUtc);
    if (record.keyGeneration != expectedKeyGeneration) {
      throw const EncryptedMemoryPolicyViolation(
        'record_key_generation_mismatch',
      );
    }
    if (_records.containsKey(record.id) || _quarantine.containsKey(record.id)) {
      throw const EncryptedMemoryPolicyViolation('record_already_exists');
    }

    _consumeForRecord(
      lease: lease,
      operation: EncryptedMemoryOperation.remember,
      record: record,
      nowUtc: nowUtc,
    );
    if (record.provenance.requiresQuarantine) {
      _quarantine[record.id] = record;
    } else {
      _records[record.id] = record;
    }
  }

  /// Returns only records that already passed deterministic admission policy.
  ///
  /// Every scope field is supplied before lookup and consumed as one exact,
  /// single-use lease. Quarantined records are intentionally indistinguishable
  /// from missing records through this API.
  EncryptedMemorySessionRecord? recall({
    required EncryptedMemoryConsentLease lease,
    required NeuraSafetyContext safetyContext,
    required String recordId,
    required String ownerId,
    required String deviceId,
    required String capsuleId,
    required EncryptedMemoryClass memoryClass,
    required EncryptedMemorySource source,
    required EncryptedMemorySensitivity sensitivity,
    required int expectedKeyGeneration,
    required DateTime nowUtc,
  }) {
    _requireAvailable(safetyContext, expectedKeyGeneration);
    _requireUtc(nowUtc);
    _requireSessionId(recordId, 'record_id');
    _requireSessionId(ownerId, 'owner_id');
    _requireSessionId(deviceId, 'device_id');
    _requireSessionId(capsuleId, 'capsule_id');

    lease.consumeFor(
      operation: EncryptedMemoryOperation.recall,
      requestedOwnerId: ownerId,
      requestedDeviceId: deviceId,
      requestedCapsuleId: capsuleId,
      memoryClass: memoryClass,
      source: source,
      sensitivity: sensitivity,
      nowUtc: nowUtc,
    );

    final record = _records[recordId];
    if (record == null ||
        !record.matchesScope(
          requestedOwnerId: ownerId,
          requestedDeviceId: deviceId,
          requestedCapsuleId: capsuleId,
          requestedClass: memoryClass,
          requestedSource: source,
          requestedSensitivity: sensitivity,
          expectedKeyGeneration: expectedKeyGeneration,
        )) {
      return null;
    }
    return record;
  }

  /// Releases or rejects one quarantined candidate after an explicit review.
  ///
  /// A release requires a verified integrity tag produced outside this class;
  /// the candidate's original source remains immutable. Rejection deletes the
  /// process-local candidate and grants no read authority.
  bool reviewQuarantined({
    required EncryptedMemoryConsentLease lease,
    required NeuraSafetyContext safetyContext,
    required String recordId,
    required String ownerId,
    required String deviceId,
    required String capsuleId,
    required EncryptedMemoryClass memoryClass,
    required EncryptedMemorySource source,
    required EncryptedMemorySensitivity sensitivity,
    required int expectedKeyGeneration,
    required DateTime nowUtc,
    required EncryptedMemoryQuarantineDisposition disposition,
    String? verifiedIntegrityTag,
  }) {
    _requireAvailable(safetyContext, expectedKeyGeneration);
    _requireUtc(nowUtc);
    _requireSessionId(recordId, 'record_id');

    lease.consumeFor(
      operation: EncryptedMemoryOperation.reviewQuarantine,
      requestedOwnerId: ownerId,
      requestedDeviceId: deviceId,
      requestedCapsuleId: capsuleId,
      memoryClass: memoryClass,
      source: source,
      sensitivity: sensitivity,
      nowUtc: nowUtc,
    );

    final record = _quarantine[recordId];
    if (record == null ||
        !record.matchesScope(
          requestedOwnerId: ownerId,
          requestedDeviceId: deviceId,
          requestedCapsuleId: capsuleId,
          requestedClass: memoryClass,
          requestedSource: source,
          requestedSensitivity: sensitivity,
          expectedKeyGeneration: expectedKeyGeneration,
        )) {
      return false;
    }

    if (disposition == EncryptedMemoryQuarantineDisposition.reject) {
      _quarantine.remove(recordId);
      return true;
    }
    if (verifiedIntegrityTag == null) {
      throw const EncryptedMemoryPolicyViolation(
        'verified_integrity_tag_required',
      );
    }
    final reviewed = record.reviewed(
      reviewedAtUtc: nowUtc,
      verifiedIntegrityTag: verifiedIntegrityTag,
    );
    if (reviewed.provenance.requiresQuarantine) {
      throw const EncryptedMemoryPolicyViolation(
        'quarantine_release_not_verified',
      );
    }
    _quarantine.remove(recordId);
    _records[recordId] = reviewed;
    return true;
  }

  /// Protective clearing is always available and grants no read or execution
  /// authority. The adapter stays suspended until explicitly resumed.
  void suspendAndClear() {
    _suspended = true;
    _records.clear();
    _quarantine.clear();
  }

  /// Starts a new empty session. Existing records are never restored.
  void resumeEmptySession() {
    _records.clear();
    _quarantine.clear();
    _suspended = false;
  }

  /// Ends the current session without changing authority or key state.
  void clearSession() {
    _records.clear();
    _quarantine.clear();
  }

  void _consumeForRecord({
    required EncryptedMemoryConsentLease lease,
    required EncryptedMemoryOperation operation,
    required EncryptedMemorySessionRecord record,
    required DateTime nowUtc,
  }) {
    lease.consumeFor(
      operation: operation,
      requestedOwnerId: record.ownerId,
      requestedDeviceId: record.deviceId,
      requestedCapsuleId: record.capsuleId,
      memoryClass: record.memoryClass,
      source: record.provenance.source,
      sensitivity: record.sensitivity,
      nowUtc: nowUtc,
    );
  }

  void _requireAvailable(
    NeuraSafetyContext context,
    int expectedKeyGeneration,
  ) {
    if (_suspended) {
      throw const EncryptedMemoryPolicyViolation('session_suspended');
    }
    if (safetyPolicy.safeModeActive) {
      throw const EncryptedMemoryPolicyViolation('safe_mode_blocked');
    }
    if (context.recoveryMode) {
      throw const EncryptedMemoryPolicyViolation('recovery_mode_blocked');
    }
    if (!context.directUserGesture) {
      throw const EncryptedMemoryPolicyViolation(
        'direct_user_gesture_required',
      );
    }
    keyLifecycle.requireUsableGeneration(expectedKeyGeneration);
  }
}

void _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw const EncryptedMemoryPolicyViolation('operation_time_not_utc');
  }
}

void _requireSessionId(String value, String code) {
  if (value.isEmpty ||
      value.length > 256 ||
      value.trim() != value ||
      _hasControlCharacter(value)) {
    throw EncryptedMemoryPolicyViolation(code);
  }
}

bool _hasControlCharacter(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
