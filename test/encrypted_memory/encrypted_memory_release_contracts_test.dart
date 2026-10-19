import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_session_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const storage = EncryptedMemoryDurableScopedAdapter.defaultStorageKey;
  const context = NeuraSafetyContext(directUserGesture: true);
  const value = 'synthetic private release fixture';
  final secrets = <String, String>{};
  late DateTime now;
  late EncryptedMemoryKeyLifecycle keys;
  late NeuraLivingSafetyPolicy safety;
  late _PausedRealCrypto crypto;
  var safeMode = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secure,
        (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return secrets[key];
        case 'write':
          secrets[key] = args['value'] as String;
          return null;
        case 'delete':
          secrets.remove(key);
          return null;
      }
      throw StateError('Unexpected synthetic credential-store operation.');
    });
    await MemoryCrypto.clearDeviceKey();
    MemoryCrypto.resumeAfterDataWipe();
    EncryptedMemoryDurableScopedAdapter.debugResetStorageRegistryForTesting();
    now = DateTime.utc(2026, 10, 19, 12);
    keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
    safeMode = false;
    safety = NeuraLivingSafetyPolicy(safeModeReader: () => safeMode);
    crypto = _PausedRealCrypto(await MemoryCrypto.demo());
  });

  tearDown(() async {
    crypto.release();
    await MemoryCrypto.clearDeviceKey();
    MemoryCrypto.resumeAfterDataWipe();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, null);
  });

  EncryptedMemoryConsentLease lease(String id, EncryptedMemoryOperation op) =>
      EncryptedMemoryConsentLease(
        id: id,
        scope: EncryptedMemoryAccessScope(
          ownerId: 'owner',
          deviceId: 'device',
          capsuleId: 'personal',
          classes: const {EncryptedMemoryClass.explicitPreference},
          sources: const {EncryptedMemorySource.authenticatedUser},
          sensitivity: EncryptedMemorySensitivity.personal,
        ),
        operations: {op},
        issuedAtUtc: now,
        expiresAtUtc: now.add(const Duration(minutes: 5)),
        directUserGesture: true,
      );

  EncryptedMemoryDurableScopedAdapter adapter(
          {bool useDefaultCrypto = false}) =>
      EncryptedMemoryDurableScopedAdapter(
        safetyPolicy: safety,
        keyLifecycle: keys,
        loadCrypto: useDefaultCrypto ? null : () async => crypto,
        utcNow: () => now,
      );

  Future<void> seed(EncryptedMemoryDurableScopedAdapter subject) =>
      subject.remember(
        lease: lease('remember', EncryptedMemoryOperation.remember),
        safetyContext: context,
        record: EncryptedMemorySessionRecord(
          id: 'record',
          ownerId: 'owner',
          deviceId: 'device',
          capsuleId: 'personal',
          memoryClass: EncryptedMemoryClass.explicitPreference,
          sensitivity: EncryptedMemorySensitivity.personal,
          provenance: EncryptedMemoryProvenance(
            source: EncryptedMemorySource.authenticatedUser,
            sourceId: 'synthetic-gesture',
            authorId: 'owner',
            reason: 'user_tapped_remember',
            trustTier: EncryptedMemoryTrustTier.authenticatedUser,
            integrityState: EncryptedMemoryIntegrityState.verified,
            integrityTag: 'sha256:0123456789abcdef',
            observedAtUtc: now,
          ),
          value: value,
          createdAtUtc: now,
          keyGeneration: keys.generation,
        ),
        expectedKeyGeneration: keys.generation,
        nowUtc: now,
      );

  EncryptedMemorySessionRecord? recall(
    EncryptedMemoryDurableScopedAdapter subject,
    EncryptedMemoryConsentLease consent, {
    DateTime? requestedAt,
  }) =>
      subject.recall(
        lease: consent,
        safetyContext: context,
        recordId: 'record',
        ownerId: 'owner',
        deviceId: 'device',
        capsuleId: 'personal',
        memoryClass: EncryptedMemoryClass.explicitPreference,
        source: EncryptedMemorySource.authenticatedUser,
        sensitivity: EncryptedMemorySensitivity.personal,
        expectedKeyGeneration: keys.generation,
        nowUtc: requestedAt ?? now,
      );

  Future<bool> correct(
    EncryptedMemoryDurableScopedAdapter subject,
    EncryptedMemoryConsentLease consent,
  ) =>
      subject.correct(
        lease: consent,
        safetyContext: context,
        recordId: 'record',
        ownerId: 'owner',
        deviceId: 'device',
        capsuleId: 'personal',
        memoryClass: EncryptedMemoryClass.explicitPreference,
        source: EncryptedMemorySource.authenticatedUser,
        sensitivity: EncryptedMemorySensitivity.personal,
        expectedKeyGeneration: keys.generation,
        nowUtc: now,
        replacementValue: 'synthetic replacement',
      );

  test('expired recall cannot backdate access using its request timestamp',
      () async {
    final subject = adapter();
    await seed(subject);
    final consent = lease('recall', EncryptedMemoryOperation.recall);
    final requestedAt = now;
    now = consent.expiresAtUtc;
    expect(
      () => recall(subject, consent, requestedAt: requestedAt),
      throwsA(isA<EncryptedMemoryPolicyViolation>()),
    );
    expect(consent.isConsumed, isFalse);
    expect(
        recall(subject, lease('fresh-recall', EncryptedMemoryOperation.recall))
            ?.value,
        value);
  });

  test('clock rollback cannot reuse the original request time', () async {
    final subject = adapter();
    await seed(subject);
    final consent = lease('recall', EncryptedMemoryOperation.recall);
    final requestedAt = now;
    now = now.subtract(const Duration(microseconds: 1));
    expect(
      () => recall(subject, consent, requestedAt: requestedAt),
      throwsA(isA<EncryptedMemoryPolicyViolation>().having(
        (e) => e.code,
        'code',
        'consent_clock_rollback',
      )),
    );
    expect(consent.isConsumed, isFalse);
  });

  test('expiry after a platform write requires explicit reconciliation', () async {
    final subject = adapter();
    await seed(subject);
    final prefs = NeuraPrefsCache.prefs;
    final before = prefs.getString(storage);
    final originalPlatform = SharedPreferencesStorePlatform.instance;
    final platform = _PausedPreferencesStore({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    });
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() async {
      platform.release();
      SharedPreferencesStorePlatform.instance = originalPlatform;
      await prefs.reload();
    });
    await prefs.reload();
    final correction = lease('correct', EncryptedMemoryOperation.correct);
    final rejected = expectLater(
      correct(subject, correction),
      throwsA(isA<EncryptedMemoryPolicyViolation>()),
    );
    await platform.started.future;
    now = correction.expiresAtUtc;
    platform.release();
    await rejected;
    // An already-issued native write cannot be recalled. Its encrypted result
    // must remain unreadable until an explicit restore reconciles disk state.
    expect(prefs.getString(storage), isNot(before));
    expect(prefs.getString(storage), isNot(contains('synthetic replacement')));
    final read = lease('unreconciled', EncryptedMemoryOperation.recall);
    expect(
      () => recall(subject, read),
      throwsA(isA<EncryptedMemoryPolicyViolation>().having(
        (e) => e.code,
        'code',
        'durable_reconciliation_required',
      )),
    );
    expect(read.isConsumed, isFalse);
    await subject.restore(
      safetyContext: context,
      expectedKeyGeneration: keys.generation,
    );
    expect(
      recall(subject, lease('fresh', EncryptedMemoryOperation.recall))?.value,
      'synthetic replacement',
    );
  });

  test(
      'expiry during encryption rolls back and blocks a queued expired mutation',
      () async {
    final subject = adapter();
    await seed(subject);
    final before = NeuraPrefsCache.prefs.getString(storage);
    crypto.pauseEncryption = true;
    final correction = lease('correct', EncryptedMemoryOperation.correct);
    final pending = correct(subject, correction);
    final rejected =
        expectLater(pending, throwsA(isA<EncryptedMemoryPolicyViolation>()));
    await crypto.started.future;
    final read = lease('read-during-commit', EncryptedMemoryOperation.recall);
    expect(
      () => recall(subject, read),
      throwsA(isA<EncryptedMemoryPolicyViolation>().having(
        (e) => e.code,
        'code',
        'durable_mutation_pending',
      )),
    );
    expect(read.isConsumed, isFalse);
    final queuedConsent =
        lease('queued-correct', EncryptedMemoryOperation.correct);
    final queued = expectLater(correct(subject, queuedConsent),
        throwsA(isA<EncryptedMemoryPolicyViolation>()));
    now = correction.expiresAtUtc;
    crypto.release();
    await rejected;
    await queued;
    expect(correction.isConsumed, isTrue);
    expect(queuedConsent.isConsumed, isFalse);
    expect(NeuraPrefsCache.prefs.getString(storage), before);
    expect(
        recall(subject, lease('fresh-recall', EncryptedMemoryOperation.recall))
            ?.value,
        value);
  });

  for (final operation in ['correction', 'restore']) {
    test('device-key destruction cancels pending $operation and cached recall',
        () async {
      final subject = adapter();
      await seed(subject);
      final before = NeuraPrefsCache.prefs.getString(storage);
      crypto.pauseEncryption = operation == 'correction';
      crypto.pauseDecryption = operation == 'restore';
      final Future<Object?> pending = operation == 'correction'
          ? correct(subject, lease('correct', EncryptedMemoryOperation.correct))
          : subject.restore(
              safetyContext: context, expectedKeyGeneration: keys.generation);
      final rejected = expectLater(pending, throwsStateError);
      await crypto.started.future;
      // Deliberately keep the policy lifecycle active: the real device-key
      // authority must independently revoke the cache and crypto operation.
      await MemoryCrypto.clearDeviceKey();
      crypto.release();
      await rejected;
      expect(NeuraPrefsCache.prefs.getString(storage), before);
      expect(
          () =>
              recall(subject, lease('recall', EncryptedMemoryOperation.recall)),
          throwsStateError);
    });
  }

  test(
      'default crypto revokes cached access after successful cleanup and rekey',
      () async {
    final subject = adapter(useDefaultCrypto: true);
    await seed(subject);
    await MemoryCrypto.clearDeviceKey();
    MemoryCrypto.resumeAfterDataWipe();
    final fresh = await MemoryCrypto.demo();
    final freshBlob =
        await fresh.encryptJson({'value': 'fresh synthetic data'});
    expect(
        () => recall(subject, lease('recall', EncryptedMemoryOperation.recall)),
        throwsStateError);
    await expectLater(crypto.inner.decryptJson(freshBlob), throwsStateError);
    await expectLater(
      adapter(useDefaultCrypto: true).restore(
          safetyContext: context, expectedKeyGeneration: keys.generation),
      throwsA(isA<EncryptedMemoryPolicyViolation>()),
    );
  });

  test(
      'corrupt authenticated storage installs no partial records and can be retried',
      () async {
    final subject = adapter();
    await seed(subject);
    final original = NeuraPrefsCache.prefs.getString(storage)!;
    expect(original, isNot(contains(value)));
    final envelope = jsonDecode(original) as Map<String, dynamic>;
    final mac = base64Decode(envelope['m'] as String);
    mac[0] ^= 1;
    envelope['m'] = base64Encode(mac);
    final corrupt = jsonEncode(envelope);
    await NeuraPrefsCache.prefs.setString(storage, corrupt);
    EncryptedMemoryDurableScopedAdapter.debugResetStorageRegistryForTesting();
    final restarted = adapter();
    await expectLater(
      restarted.restore(
          safetyContext: context, expectedKeyGeneration: keys.generation),
      throwsA(isA<Exception>()),
    );
    expect(restarted.recordCount, 0);
    expect(restarted.quarantinedRecordCount, 0);
    expect(NeuraPrefsCache.prefs.getString(storage), corrupt);
    expect(recall(restarted, lease('missing', EncryptedMemoryOperation.recall)),
        isNull);
    await NeuraPrefsCache.prefs.setString(storage, original);
    await restarted.restore(
        safetyContext: context, expectedKeyGeneration: keys.generation);
    expect(
        recall(restarted, lease('recovered', EncryptedMemoryOperation.recall))
            ?.value,
        value);
  });

  test('Safe Mode during a pending restore blocks publication and recall',
      () async {
    final subject = adapter();
    await seed(subject);
    crypto.pauseDecryption = true;
    final pending = subject.restore(
        safetyContext: context, expectedKeyGeneration: keys.generation);
    final rejected =
        expectLater(pending, throwsA(isA<EncryptedMemoryPolicyViolation>()));
    await crypto.started.future;
    safeMode = true;
    crypto.release();
    await rejected;
    final read = lease('recall-safe', EncryptedMemoryOperation.recall);
    expect(() => recall(subject, read),
        throwsA(isA<EncryptedMemoryPolicyViolation>()));
    expect(read.isConsumed, isFalse);
  });
}

final class _PausedRealCrypto implements EncryptedMemoryDurableCrypto {
  _PausedRealCrypto(this.inner);

  final MemoryCrypto inner;
  final started = Completer<void>();
  final _released = Completer<void>();
  bool pauseEncryption = false;
  bool pauseDecryption = false;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  Future<void> _pause() async {
    if (!started.isCompleted) started.complete();
    await _released.future;
  }

  @override
  Object get authorityToken {
    inner.requireActiveKey();
    return inner;
  }

  @override
  Future<String> encryptJson(Map<String, dynamic> json) async {
    if (pauseEncryption) await _pause();
    return inner.encryptJson(json);
  }

  @override
  Future<Map<String, dynamic>> decryptJson(String blob) async {
    if (pauseDecryption) await _pause();
    return inner.decryptJson(blob);
  }
}

final class _PausedPreferencesStore extends SharedPreferencesStorePlatform {
  _PausedPreferencesStore(this.data);

  final Map<String, Object> data;
  final started = Completer<void>();
  final _released = Completer<void>();

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.from(data);

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (!started.isCompleted) started.complete();
    await _released.future;
    data[key] = value;
    return true;
  }
}
