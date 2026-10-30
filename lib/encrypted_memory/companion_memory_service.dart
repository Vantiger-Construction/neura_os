import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../core/memory/memory_crypto.dart';
import '../living_intelligence/neura_safety_policy.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';
import 'encrypted_memory_contracts.dart';
import 'encrypted_memory_durable_scoped_adapter.dart';
import 'encrypted_memory_session_adapter.dart';

enum CompanionMemoryUse { review, prompt, remember, wipe }

/// One user gesture, one operation and one destination. A review grant cannot
/// be reused for a prompt, nor a recall grant for a write. Nothing is persisted.
final class CompanionMemoryPermission {
  CompanionMemoryPermission._(this._owner, this.use, this.lease);

  final CompanionMemoryService _owner;
  final CompanionMemoryUse use;
  final EncryptedMemoryConsentLease lease;
  Timer? _expiry;

  CompanionMemoryService get service => _owner;

  void requireCurrent() => _owner._validate(this, use, unused: false);

  void revoke() {
    lease.revoke();
    _expiry?.cancel();
    _owner._permissionRevoked(this);
  }
}

/// Production owner of explicitly authored companion notes for this device's
/// local profile. It never imports chat, journals, therapy or legacy summaries.
/// The local profile is independent of cloud sign-in and is never synced.
final class CompanionMemoryService extends ChangeNotifier
    with WidgetsBindingObserver {
  CompanionMemoryService({
    required this.scope,
    required this.keyLifecycle,
    required this.safetyPolicy,
    required EncryptedMemoryDurableCrypto crypto,
    DateTime Function()? utcNow,
    bool Function()? recoveryMode,
    String storageKey = EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
  })  : _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
        _recoveryMode =
            recoveryMode ?? (() => SafeBoot.instance.restartRequired.value),
        _adapter = EncryptedMemoryDurableScopedAdapter(
          safetyPolicy: safetyPolicy,
          keyLifecycle: keyLifecycle,
          loadCrypto: () async => crypto,
          utcNow: utcNow,
          storageKey: storageKey,
        ) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (scope.classes.single != EncryptedMemoryClass.userAuthoredNote ||
        scope.sources.single != EncryptedMemorySource.authenticatedUser ||
        scope.sensitivity != EncryptedMemorySensitivity.personal) {
      throw const EncryptedMemoryPolicyViolation('companion_scope_mismatch');
    }
    _owners.add(this);
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafeMode);
    SafeBoot.instance.restartRequired.addListener(_onSafeMode);
  }

  static Future<CompanionMemoryService>? _local;
  static final Set<CompanionMemoryService> _owners = {};
  static const identityKey = 'neura.encrypted_memory.local_profile.v1';
  static const _context = NeuraSafetyContext(directUserGesture: true);

  /// Called only by explicit memory controls, never at app startup or by the
  /// prompt builder. The identifier is random, non-secret local scope metadata.
  static Future<CompanionMemoryService> local() {
    if (SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      throw const EncryptedMemoryPolicyViolation('memory_unavailable');
    }
    return _local ??= _loadLocal().onError((Object error, StackTrace stack) {
      _local = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  static Future<CompanionMemoryService> _loadLocal() async {
    final prefs = NeuraPrefsCache.prefs;
    var id = prefs.getString(identityKey);
    if (id == null) {
      // Missing identity must never reassign existing ciphertext to a new user.
      if (prefs.containsKey(
        EncryptedMemoryDurableScopedAdapter.defaultStorageKey,
      )) {
        throw const EncryptedMemoryPolicyViolation('local_profile_missing');
      }
      id = const Uuid().v4();
      if (!await prefs.setString(identityKey, id)) {
        throw const EncryptedMemoryPolicyViolation(
          'local_profile_write_failed',
        );
      }
      await prefs.reload();
      if (prefs.getString(identityKey) != id) {
        throw const EncryptedMemoryPolicyViolation(
          'local_profile_write_failed',
        );
      }
    }
    final crypto = await MemoryCrypto.demo();
    crypto.requireOsBackedKey();
    return CompanionMemoryService(
      scope: EncryptedMemoryAccessScope(
        ownerId: 'local-profile:$id',
        deviceId: 'installation:$id',
        capsuleId: 'companion-notes',
        classes: const {EncryptedMemoryClass.userAuthoredNote},
        sources: const {EncryptedMemorySource.authenticatedUser},
        sensitivity: EncryptedMemorySensitivity.personal,
      ),
      keyLifecycle: EncryptedMemoryKeyLifecycle()..provisionVerifiedKey(),
      safetyPolicy: NeuraLivingSafetyPolicy(),
      crypto: MemoryCryptoDurableAdapter(crypto),
    );
  }

  static void suspendAllForDataWipe() {
    for (final owner in _owners.toList()) {
      owner._wiped = true;
      owner.revokePermissions();
    }
  }

  final EncryptedMemoryAccessScope scope;
  final EncryptedMemoryKeyLifecycle keyLifecycle;
  final NeuraLivingSafetyPolicy safetyPolicy;
  final EncryptedMemoryDurableScopedAdapter _adapter;
  final DateTime Function() _utcNow;
  final bool Function() _recoveryMode;
  final Set<CompanionMemoryPermission> _permissions = {};
  bool _foreground = true;
  bool _wiped = false;
  bool _disposed = false;

  bool get isAvailable {
    try {
      _requireAvailable();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// UI callers invoke this only after the named control's direct gesture.
  /// Merely opening the memory screen, typing chat or saving a journal is not
  /// such a gesture. No setting or previous cloud approval supplies consent.
  CompanionMemoryPermission authorize(
    CompanionMemoryUse use, {
    required bool directUserGesture,
  }) {
    _requireAvailable();
    if (!directUserGesture) {
      throw const EncryptedMemoryPolicyViolation(
        'direct_user_gesture_required',
      );
    }
    final now = _utcNow();
    final permission = CompanionMemoryPermission._(
      this,
      use,
      EncryptedMemoryConsentLease(
        id: const Uuid().v4(),
        scope: scope,
        operations: {_operation(use)},
        issuedAtUtc: now,
        expiresAtUtc: now.add(const Duration(minutes: 5)),
        directUserGesture: true,
      ),
    );
    _permissions.add(permission);
    permission._expiry = Timer(const Duration(minutes: 5), permission.revoke);
    return permission;
  }

  Future<List<EncryptedMemorySessionRecord>> recall(
    CompanionMemoryPermission? permission, {
    required CompanionMemoryUse use,
  }) async {
    if (use != CompanionMemoryUse.review && use != CompanionMemoryUse.prompt) {
      throw const EncryptedMemoryPolicyViolation('recall_destination_mismatch');
    }
    await _restore(permission, use);
    final records = _adapter.recallScope(
      lease: permission!.lease,
      safetyContext: _context,
      scope: scope,
      expectedKeyGeneration: keyLifecycle.generation,
      nowUtc: _utcNow(),
    );
    _validate(permission, use, unused: false);
    return records;
  }

  Future<void> remember(
    CompanionMemoryPermission? permission,
    String note,
  ) async {
    _validate(permission, CompanionMemoryUse.remember);
    final value = note.trim();
    if (value.isEmpty ||
        value.length > 1000 ||
        value.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      throw const EncryptedMemoryPolicyViolation('invalid_companion_note');
    }
    await _restore(permission, CompanionMemoryUse.remember);
    if (_adapter.recordCount >= 100) {
      throw const EncryptedMemoryPolicyViolation('companion_notes_full');
    }
    final digest = await Sha256().hash(utf8.encode(value));
    _validate(permission, CompanionMemoryUse.remember);
    final now = _utcNow();
    await _adapter.remember(
      lease: permission!.lease,
      safetyContext: _context,
      record: EncryptedMemorySessionRecord(
        id: const Uuid().v4(),
        ownerId: scope.ownerId,
        deviceId: scope.deviceId,
        capsuleId: scope.capsuleId,
        memoryClass: scope.classes.single,
        sensitivity: scope.sensitivity,
        provenance: EncryptedMemoryProvenance(
          source: scope.sources.single,
          sourceId: permission.lease.id,
          authorId: scope.ownerId,
          reason: 'user_tapped_remember_note',
          trustTier: EncryptedMemoryTrustTier.userReviewed,
          integrityState: EncryptedMemoryIntegrityState.verified,
          integrityTag: base64UrlEncode(digest.bytes),
          observedAtUtc: now,
          reviewedAtUtc: now,
        ),
        value: value,
        createdAtUtc: now,
        keyGeneration: keyLifecycle.generation,
      ),
      expectedKeyGeneration: keyLifecycle.generation,
      nowUtc: now,
      recordLimit: 100,
    );
    _validate(permission, CompanionMemoryUse.remember, unused: false);
  }

  Future<void> wipeNotes(CompanionMemoryPermission? permission) async {
    _validate(permission, CompanionMemoryUse.wipe);
    for (final existing in _permissions.toList()) {
      if (!identical(existing, permission)) existing.revoke();
    }
    await _restore(permission, CompanionMemoryUse.wipe);
    // An empty registry has no attached crypto authority and needs no deletion.
    if (_adapter.recordCount == 0 && _adapter.quarantinedRecordCount == 0) {
      permission!.lease.consumeFor(
        operation: EncryptedMemoryOperation.wipe,
        requestedOwnerId: scope.ownerId,
        requestedDeviceId: scope.deviceId,
        requestedCapsuleId: scope.capsuleId,
        memoryClass: scope.classes.single,
        source: scope.sources.single,
        sensitivity: scope.sensitivity,
        nowUtc: _utcNow(),
      );
      return;
    }
    await _adapter.wipeScope(
      lease: permission!.lease,
      safetyContext: _context,
      ownerId: scope.ownerId,
      deviceId: scope.deviceId,
      capsuleId: scope.capsuleId,
      memoryClass: scope.classes.single,
      source: scope.sources.single,
      sensitivity: scope.sensitivity,
      expectedKeyGeneration: keyLifecycle.generation,
      nowUtc: _utcNow(),
      contract: const EncryptedMemoryWipeContract(
        stopWritersFirst: true,
        deleteCiphertext: true,
        destroyKey: false,
        verifyCiphertextDeletion: true,
        verifyKeyDeletion: false,
      ),
    );
    _validate(permission, CompanionMemoryUse.wipe, unused: false);
    revokePermissions();
  }

  Future<void> _restore(
    CompanionMemoryPermission? permission,
    CompanionMemoryUse use,
  ) async {
    _validate(permission, use);
    await _adapter.restore(
      safetyContext: _context,
      expectedKeyGeneration: keyLifecycle.generation,
    );
    _validate(permission, use);
  }

  void _validate(
    CompanionMemoryPermission? permission,
    CompanionMemoryUse use, {
    bool unused = true,
  }) {
    _requireAvailable();
    if (permission == null ||
        !identical(permission._owner, this) ||
        !_permissions.contains(permission) ||
        permission.use != use ||
        !permission.lease.isWithinLifetime(_utcNow()) ||
        (unused &&
            !permission.lease.authorizes(
              operation: _operation(use),
              requestedOwnerId: scope.ownerId,
              requestedDeviceId: scope.deviceId,
              requestedCapsuleId: scope.capsuleId,
              memoryClass: scope.classes.single,
              source: scope.sources.single,
              sensitivity: scope.sensitivity,
              nowUtc: _utcNow(),
            ))) {
      throw const EncryptedMemoryPolicyViolation('companion_consent_required');
    }
  }

  void _requireAvailable() {
    if (_disposed ||
        _wiped ||
        !_foreground ||
        safetyPolicy.safeModeActive ||
        _recoveryMode()) {
      throw const EncryptedMemoryPolicyViolation('memory_unavailable');
    }
    keyLifecycle.requireUsableGeneration(keyLifecycle.generation);
  }

  void revokePermissions() {
    for (final permission in _permissions.toList()) {
      permission.revoke();
    }
    notifyListeners();
  }

  void _permissionRevoked(CompanionMemoryPermission permission) {
    if (_permissions.remove(permission)) notifyListeners();
  }

  void _onSafeMode() {
    if (safetyPolicy.safeModeActive || _recoveryMode()) revokePermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) revokePermissions();
  }

  @override
  void dispose() {
    revokePermissions();
    _disposed = true;
    _owners.remove(this);
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafeMode);
    SafeBoot.instance.restartRequired.removeListener(_onSafeMode);
    super.dispose();
  }

  static EncryptedMemoryOperation _operation(CompanionMemoryUse use) =>
      switch (use) {
        CompanionMemoryUse.review ||
        CompanionMemoryUse.prompt =>
          EncryptedMemoryOperation.recall,
        CompanionMemoryUse.remember => EncryptedMemoryOperation.remember,
        CompanionMemoryUse.wipe => EncryptedMemoryOperation.wipe,
      };
}
