import '../core/memory/memory_crypto.dart';
import '../living_intelligence/neura_safety_policy.dart';
import '../startup/neura_prefs_cache.dart';
import 'encrypted_memory_contracts.dart';
import 'encrypted_memory_session_adapter.dart';

abstract interface class EncryptedMemoryDurableCrypto {
  Future<String> encryptJson(Map<String, dynamic> json);
  Future<Map<String, dynamic>> decryptJson(String blob);
}

final class MemoryCryptoDurableAdapter implements EncryptedMemoryDurableCrypto {
  const MemoryCryptoDurableAdapter(this.crypto);

  final MemoryCrypto crypto;

  @override
  Future<Map<String, dynamic>> decryptJson(String blob) =>
      crypto.decryptJson(blob);

  @override
  Future<String> encryptJson(Map<String, dynamic> json) =>
      crypto.encryptJson(json);
}

/// Durable, exact-scope memory slice.
///
/// This adapter is intentionally narrow: it stores only encrypted records under
/// one preference key, restores only records whose key generation is still
/// active, and exposes no broad query API or legacy plaintext migration path.
final class EncryptedMemoryDurableScopedAdapter {
  EncryptedMemoryDurableScopedAdapter({
    required this.safetyPolicy,
    required this.keyLifecycle,
    Future<EncryptedMemoryDurableCrypto> Function()? loadCrypto,
    this.storageKey = defaultStorageKey,
  })  : _loadCrypto = loadCrypto ??
            (() async => MemoryCryptoDurableAdapter(await MemoryCrypto.demo())),
        _state = _DurableScopedStorageRegistry.stateFor(storageKey) {
    if (!NeuraPrefsCache.prefs.containsKey(storageKey)) {
      _state.resetIfStorageMissing();
    }
  }

  static const defaultStorageKey = 'neura.encrypted_memory.scoped.v1';

  final NeuraLivingSafetyPolicy safetyPolicy;
  final EncryptedMemoryKeyLifecycle keyLifecycle;
  final Future<EncryptedMemoryDurableCrypto> Function() _loadCrypto;
  final String storageKey;
  final _DurableScopedStorageState _state;

  Map<String, EncryptedMemorySessionRecord> get _records => _state.records;
  Map<String, EncryptedMemorySessionRecord> get _quarantine =>
      _state.quarantine;

  int get recordCount => _records.length;
  int get quarantinedRecordCount => _quarantine.length;

  Future<void> restore({
    required NeuraSafetyContext safetyContext,
    required int expectedKeyGeneration,
  }) =>
      _serializedMutation(
        () async {
          _requireAvailable(safetyContext, expectedKeyGeneration);
          final blob = NeuraPrefsCache.prefs.getString(storageKey);
          if (blob == null) {
            _requireAvailable(safetyContext, expectedKeyGeneration);
            _publishRestored(
              records: const {},
              quarantine: const {},
            );
            return;
          }

          final crypto = await _loadCrypto();
          _requireAvailable(safetyContext, expectedKeyGeneration);
          final clear = await crypto.decryptJson(blob);
          _requireAvailable(safetyContext, expectedKeyGeneration);
          if (clear['schema'] != 1) {
            throw const EncryptedMemoryPolicyViolation(
              'durable_schema_mismatch',
            );
          }

          final restoredRecords = <String, EncryptedMemorySessionRecord>{};
          final restoredQuarantine = <String, EncryptedMemorySessionRecord>{};
          for (final raw in (clear['records'] as List? ?? const [])) {
            final record =
                _recordFromJson(Map<String, dynamic>.from(raw as Map));
            _requireRestorable(record, expectedKeyGeneration);
            restoredRecords[record.id] = record;
          }
          for (final raw in (clear['quarantine'] as List? ?? const [])) {
            final record =
                _recordFromJson(Map<String, dynamic>.from(raw as Map));
            _requireRestorable(record, expectedKeyGeneration);
            restoredQuarantine[record.id] = record;
          }

          _requireAvailable(safetyContext, expectedKeyGeneration);
          _publishRestored(
            records: restoredRecords,
            quarantine: restoredQuarantine,
          );
        },
        allowReconciliation: true,
      );

  Future<void> remember({
    required EncryptedMemoryConsentLease lease,
    required NeuraSafetyContext safetyContext,
    required EncryptedMemorySessionRecord record,
    required int expectedKeyGeneration,
    required DateTime nowUtc,
  }) =>
      _serializedMutation(() async {
        _requireAvailable(safetyContext, expectedKeyGeneration);
        _requireUtc(nowUtc);
        _requireRestorable(record, expectedKeyGeneration);
        if (_records.containsKey(record.id) ||
            _quarantine.containsKey(record.id)) {
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
        await _persist(
          safetyContext: safetyContext,
          expectedKeyGeneration: expectedKeyGeneration,
        );
      });

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
    if (_state.reconciliationRequired) {
      throw const EncryptedMemoryPolicyViolation(
        'durable_reconciliation_required',
      );
    }
    _requireAvailable(safetyContext, expectedKeyGeneration);
    _requireUtc(nowUtc);
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
        !_matches(
          record,
          ownerId,
          deviceId,
          capsuleId,
          memoryClass,
          source,
          sensitivity,
          expectedKeyGeneration,
        )) {
      return null;
    }
    return record;
  }

  Future<bool> correct({
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
    required String replacementValue,
  }) =>
      _serializedMutation(() async {
        _requireAvailable(safetyContext, expectedKeyGeneration);
        _requireUtc(nowUtc);
        lease.consumeFor(
          operation: EncryptedMemoryOperation.correct,
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
            !_matches(
              record,
              ownerId,
              deviceId,
              capsuleId,
              memoryClass,
              source,
              sensitivity,
              expectedKeyGeneration,
            )) {
          return false;
        }
        _records[recordId] = EncryptedMemorySessionRecord(
          id: record.id,
          ownerId: record.ownerId,
          deviceId: record.deviceId,
          capsuleId: record.capsuleId,
          memoryClass: record.memoryClass,
          sensitivity: record.sensitivity,
          provenance: record.provenance,
          value: replacementValue,
          createdAtUtc: record.createdAtUtc,
          keyGeneration: record.keyGeneration,
        );
        await _persist(
          safetyContext: safetyContext,
          expectedKeyGeneration: expectedKeyGeneration,
        );
        return true;
      });

  Future<bool> forget({
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
  }) =>
      _serializedMutation(() async {
        _requireAvailable(safetyContext, expectedKeyGeneration);
        _requireUtc(nowUtc);
        lease.consumeFor(
          operation: EncryptedMemoryOperation.forget,
          requestedOwnerId: ownerId,
          requestedDeviceId: deviceId,
          requestedCapsuleId: capsuleId,
          memoryClass: memoryClass,
          source: source,
          sensitivity: sensitivity,
          nowUtc: nowUtc,
        );
        final removed = _removeMatching(
          recordId,
          ownerId,
          deviceId,
          capsuleId,
          memoryClass,
          source,
          sensitivity,
          expectedKeyGeneration,
        );
        if (removed) {
          await _persist(
            safetyContext: safetyContext,
            expectedKeyGeneration: expectedKeyGeneration,
          );
        }
        return removed;
      });

  Future<void> wipeScope({
    required EncryptedMemoryConsentLease lease,
    required NeuraSafetyContext safetyContext,
    required String ownerId,
    required String deviceId,
    required String capsuleId,
    required EncryptedMemoryClass memoryClass,
    required EncryptedMemorySource source,
    required EncryptedMemorySensitivity sensitivity,
    required int expectedKeyGeneration,
    required DateTime nowUtc,
    required EncryptedMemoryWipeContract contract,
  }) =>
      _serializedMutation(() async {
        contract.validateScopedCiphertextOnly();
        _requireAvailable(safetyContext, expectedKeyGeneration);
        _requireUtc(nowUtc);
        lease.consumeFor(
          operation: EncryptedMemoryOperation.wipe,
          requestedOwnerId: ownerId,
          requestedDeviceId: deviceId,
          requestedCapsuleId: capsuleId,
          memoryClass: memoryClass,
          source: source,
          sensitivity: sensitivity,
          nowUtc: nowUtc,
        );
        _records.removeWhere(
          (_, record) => _matches(
            record,
            ownerId,
            deviceId,
            capsuleId,
            memoryClass,
            source,
            sensitivity,
            expectedKeyGeneration,
          ),
        );
        _quarantine.removeWhere(
          (_, record) => _matches(
            record,
            ownerId,
            deviceId,
            capsuleId,
            memoryClass,
            source,
            sensitivity,
            expectedKeyGeneration,
          ),
        );
        await _persist(
          safetyContext: safetyContext,
          expectedKeyGeneration: expectedKeyGeneration,
        );
      });

  Future<bool> reviewQuarantined({
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
  }) =>
      _serializedMutation(() async {
        _requireAvailable(safetyContext, expectedKeyGeneration);
        _requireUtc(nowUtc);
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
            !_matches(
              record,
              ownerId,
              deviceId,
              capsuleId,
              memoryClass,
              source,
              sensitivity,
              expectedKeyGeneration,
            )) {
          return false;
        }
        if (disposition == EncryptedMemoryQuarantineDisposition.release) {
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
        } else {
          _quarantine.remove(recordId);
        }
        await _persist(
          safetyContext: safetyContext,
          expectedKeyGeneration: expectedKeyGeneration,
        );
        return true;
      });

  void _publishRestored({
    required Map<String, EncryptedMemorySessionRecord> records,
    required Map<String, EncryptedMemorySessionRecord> quarantine,
  }) {
    _records
      ..clear()
      ..addAll(records);
    _quarantine
      ..clear()
      ..addAll(quarantine);
    _state.clearReconciliation();
  }

  bool _removeMatching(
    String recordId,
    String ownerId,
    String deviceId,
    String capsuleId,
    EncryptedMemoryClass memoryClass,
    EncryptedMemorySource source,
    EncryptedMemorySensitivity sensitivity,
    int expectedKeyGeneration,
  ) {
    final record = _records[recordId] ?? _quarantine[recordId];
    if (record == null ||
        !_matches(
          record,
          ownerId,
          deviceId,
          capsuleId,
          memoryClass,
          source,
          sensitivity,
          expectedKeyGeneration,
        )) {
      return false;
    }
    _records.remove(recordId);
    _quarantine.remove(recordId);
    return true;
  }

  bool _matches(
    EncryptedMemorySessionRecord record,
    String ownerId,
    String deviceId,
    String capsuleId,
    EncryptedMemoryClass memoryClass,
    EncryptedMemorySource source,
    EncryptedMemorySensitivity sensitivity,
    int expectedKeyGeneration,
  ) =>
      record.matchesScope(
        requestedOwnerId: ownerId,
        requestedDeviceId: deviceId,
        requestedCapsuleId: capsuleId,
        requestedClass: memoryClass,
        requestedSource: source,
        requestedSensitivity: sensitivity,
        expectedKeyGeneration: expectedKeyGeneration,
      );

  Future<T> _serializedMutation<T>(
    Future<T> Function() action, {
    bool allowReconciliation = false,
  }) {
    final previous = _state.mutationTail;
    _state.startMutation();
    final result = previous.then((_) async {
      if (_state.reconciliationRequired && !allowReconciliation) {
        throw const EncryptedMemoryPolicyViolation(
          'durable_reconciliation_required',
        );
      }
      final recordsBefore = Map<String, EncryptedMemorySessionRecord>.of(
        _records,
      );
      final quarantineBefore = Map<String, EncryptedMemorySessionRecord>.of(
        _quarantine,
      );
      try {
        return await action();
      } catch (error, stackTrace) {
        _records
          ..clear()
          ..addAll(recordsBefore);
        _quarantine
          ..clear()
          ..addAll(quarantineBefore);
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
    _state.mutationTail = result
        .whenComplete(_state.finishMutation)
        .then<void>((_) {}, onError: (Object error, StackTrace stackTrace) {});
    return result;
  }

  Future<void> _persist({
    required NeuraSafetyContext safetyContext,
    required int expectedKeyGeneration,
  }) async {
    _requireAvailable(safetyContext, expectedKeyGeneration);
    if (_records.isEmpty && _quarantine.isEmpty) {
      var removeAttempted = false;
      try {
        _requireAvailable(safetyContext, expectedKeyGeneration);
        removeAttempted = true;
        final removed = await NeuraPrefsCache.prefs.remove(storageKey);
        await NeuraPrefsCache.prefs.reload();
        if (!removed || NeuraPrefsCache.prefs.containsKey(storageKey)) {
          throw const EncryptedMemoryPolicyViolation('durable_remove_failed');
        }
        _requireAvailable(safetyContext, expectedKeyGeneration);
      } catch (error, stackTrace) {
        if (removeAttempted) _state.requireReconciliation();
        try {
          await NeuraPrefsCache.prefs.reload();
        } catch (_) {}
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    final clear = {
      'schema': 1,
      'records': _records.values.map(_recordToJson).toList(),
      'quarantine': _quarantine.values.map(_recordToJson).toList(),
    };
    final blob = await (await _loadCrypto()).encryptJson(clear);
    _requireAvailable(safetyContext, expectedKeyGeneration);
    var writeAttempted = false;
    try {
      writeAttempted = true;
      final saved = await NeuraPrefsCache.prefs.setString(storageKey, blob);
      await NeuraPrefsCache.prefs.reload();
      if (!saved || NeuraPrefsCache.prefs.getString(storageKey) != blob) {
        throw const EncryptedMemoryPolicyViolation('durable_write_failed');
      }
      _requireAvailable(safetyContext, expectedKeyGeneration);
    } catch (error, stackTrace) {
      if (writeAttempted) _state.requireReconciliation();
      try {
        await NeuraPrefsCache.prefs.reload();
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
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

  void _requireRestorable(
    EncryptedMemorySessionRecord record,
    int expectedKeyGeneration,
  ) {
    if (record.keyGeneration != expectedKeyGeneration) {
      throw const EncryptedMemoryPolicyViolation(
        'record_key_generation_mismatch',
      );
    }
  }
}

final class _DurableScopedStorageRegistry {
  static final Map<String, _DurableScopedStorageState> _states = {};

  static _DurableScopedStorageState stateFor(String storageKey) =>
      _states.putIfAbsent(storageKey, _DurableScopedStorageState.new);
}

final class _DurableScopedStorageState {
  final Map<String, EncryptedMemorySessionRecord> records = {};
  final Map<String, EncryptedMemorySessionRecord> quarantine = {};
  Future<void> mutationTail = Future<void>.value();
  bool reconciliationRequired = false;
  int pendingMutations = 0;

  void startMutation() {
    pendingMutations++;
  }

  void finishMutation() {
    pendingMutations--;
  }

  void requireReconciliation() {
    reconciliationRequired = true;
  }

  void clearReconciliation() {
    reconciliationRequired = false;
  }

  void resetIfStorageMissing() {
    if (pendingMutations > 0) return;
    records.clear();
    quarantine.clear();
    reconciliationRequired = false;
    mutationTail = Future<void>.value();
  }
}

Map<String, dynamic> _recordToJson(EncryptedMemorySessionRecord record) => {
      'id': record.id,
      'ownerId': record.ownerId,
      'deviceId': record.deviceId,
      'capsuleId': record.capsuleId,
      'memoryClass': record.memoryClass.name,
      'sensitivity': record.sensitivity.name,
      'provenance': _provenanceToJson(record.provenance),
      'value': record.value,
      'createdAtUtc': record.createdAtUtc.toIso8601String(),
      'keyGeneration': record.keyGeneration,
    };

Map<String, dynamic> _provenanceToJson(EncryptedMemoryProvenance provenance) =>
    {
      'source': provenance.source.name,
      'sourceId': provenance.sourceId,
      'authorId': provenance.authorId,
      'reason': provenance.reason,
      'trustTier': provenance.trustTier.name,
      'integrityState': provenance.integrityState.name,
      'integrityTag': provenance.integrityTag,
      'observedAtUtc': provenance.observedAtUtc.toIso8601String(),
      'reviewedAtUtc': provenance.reviewedAtUtc?.toIso8601String(),
    };

EncryptedMemorySessionRecord _recordFromJson(Map<String, dynamic> json) =>
    EncryptedMemorySessionRecord(
      id: json['id'] as String,
      ownerId: json['ownerId'] as String,
      deviceId: json['deviceId'] as String,
      capsuleId: json['capsuleId'] as String,
      memoryClass: EncryptedMemoryClass.values.byName(
        json['memoryClass'] as String,
      ),
      sensitivity: EncryptedMemorySensitivity.values.byName(
        json['sensitivity'] as String,
      ),
      provenance: _provenanceFromJson(
        Map<String, dynamic>.from(json['provenance'] as Map),
      ),
      value: json['value'] as String,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
      keyGeneration: json['keyGeneration'] as int,
    );

EncryptedMemoryProvenance _provenanceFromJson(Map<String, dynamic> json) =>
    EncryptedMemoryProvenance(
      source: EncryptedMemorySource.values.byName(json['source'] as String),
      sourceId: json['sourceId'] as String,
      authorId: json['authorId'] as String,
      reason: json['reason'] as String,
      trustTier: EncryptedMemoryTrustTier.values.byName(
        json['trustTier'] as String,
      ),
      integrityState: EncryptedMemoryIntegrityState.values.byName(
        json['integrityState'] as String,
      ),
      integrityTag: json['integrityTag'] as String?,
      observedAtUtc: DateTime.parse(json['observedAtUtc'] as String).toUtc(),
      reviewedAtUtc: json['reviewedAtUtc'] == null
          ? null
          : DateTime.parse(json['reviewedAtUtc'] as String).toUtc(),
    );

void _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw const EncryptedMemoryPolicyViolation('operation_time_not_utc');
  }
}
