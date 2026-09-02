import '../living_intelligence/neura_safety_policy.dart';
import 'encrypted_memory_contracts.dart';

/// One explicitly remembered value retained only for this process lifetime.
///
/// The adapter deliberately has no serialization surface. Records disappear
/// when [clearSession] is called or the process exits.
final class EncryptedMemorySessionRecord {
  EncryptedMemorySessionRecord({
    required this.id,
    required this.capsuleId,
    required this.memoryClass,
    required this.value,
    required this.createdAtUtc,
    required this.keyGeneration,
  }) {
    _requireSessionId(id, 'record_id');
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
  final String capsuleId;
  final EncryptedMemoryClass memoryClass;
  final String value;
  final DateTime createdAtUtc;
  final int keyGeneration;
}

/// Consent-gated, process-local encrypted-memory runtime seam.
///
/// This adapter provides explicit remember and recall only. It performs no
/// filesystem or database writes, encryption, export, wipe, migration,
/// background capture, inference, device sync, or Action Loom operation.
/// An already verified key lifecycle is still required as a generation-bound
/// access gate so a later durable adapter cannot bypass the foundation.
final class EncryptedMemorySessionAdapter {
  EncryptedMemorySessionAdapter({
    required this.safetyPolicy,
    required this.keyLifecycle,
  });

  final NeuraLivingSafetyPolicy safetyPolicy;
  final EncryptedMemoryKeyLifecycle keyLifecycle;
  final Map<String, EncryptedMemorySessionRecord> _records = {};

  bool _suspended = false;

  int get recordCount => _records.length;
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
    if (_records.containsKey(record.id)) {
      throw const EncryptedMemoryPolicyViolation('record_already_exists');
    }

    lease.consumeFor(
      requestedCapsuleId: record.capsuleId,
      operation: EncryptedMemoryOperation.remember,
      memoryClass: record.memoryClass,
      nowUtc: nowUtc,
    );
    _records[record.id] = record;
  }

  EncryptedMemorySessionRecord? recall({
    required EncryptedMemoryConsentLease lease,
    required NeuraSafetyContext safetyContext,
    required String recordId,
    required String capsuleId,
    required EncryptedMemoryClass memoryClass,
    required int expectedKeyGeneration,
    required DateTime nowUtc,
  }) {
    _requireAvailable(safetyContext, expectedKeyGeneration);
    _requireUtc(nowUtc);
    _requireSessionId(recordId, 'record_id');
    _requireSessionId(capsuleId, 'capsule_id');

    lease.consumeFor(
      requestedCapsuleId: capsuleId,
      operation: EncryptedMemoryOperation.recall,
      memoryClass: memoryClass,
      nowUtc: nowUtc,
    );

    final record = _records[recordId];
    if (record == null ||
        record.capsuleId != capsuleId ||
        record.memoryClass != memoryClass ||
        record.keyGeneration != expectedKeyGeneration) {
      return null;
    }
    return record;
  }

  /// Protective clearing is always available and grants no read or execution
  /// authority. The adapter stays suspended until explicitly resumed.
  void suspendAndClear() {
    _suspended = true;
    _records.clear();
  }

  /// Starts a new empty session. Existing records are never restored.
  void resumeEmptySession() {
    _records.clear();
    _suspended = false;
  }

  /// Ends the current session without changing authority or key state.
  void clearSession() {
    _records.clear();
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
