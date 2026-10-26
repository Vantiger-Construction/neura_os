import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

import 'data_wipe_fixture.dart';

class CompanionMemoryFixture {
  CompanionMemoryFixture._(this.disk, this.crypto);
  final DataWipeFixture disk;
  final PausedCompanionCrypto crypto;
  DateTime now = DateTime.utc(2026, 10, 21, 12);
  final keys = EncryptedMemoryKeyLifecycle()..provisionVerifiedKey();
  final safety = NeuraLivingSafetyPolicy();
  bool recovery = false;
  late final CompanionMemoryService memory = owner();

  EncryptedMemoryAccessScope scope(
          {String owner = 'local-profile',
          String device = 'device',
          String capsule = 'notes',
          EncryptedMemoryClass memoryClass =
              EncryptedMemoryClass.userAuthoredNote,
          EncryptedMemorySource source =
              EncryptedMemorySource.authenticatedUser,
          EncryptedMemorySensitivity sensitivity =
              EncryptedMemorySensitivity.personal}) =>
      EncryptedMemoryAccessScope(
        ownerId: owner,
        deviceId: device,
        capsuleId: capsule,
        classes: {memoryClass},
        sources: {source},
        sensitivity: sensitivity,
      );

  CompanionMemoryService owner(
      {EncryptedMemoryAccessScope? accessScope,
      String storageKey =
          EncryptedMemoryDurableScopedAdapter.defaultStorageKey}) {
    final service = CompanionMemoryService(
        scope: accessScope ?? scope(),
        keyLifecycle: keys,
        safetyPolicy: safety,
        crypto: crypto,
        utcNow: () => now,
        recoveryMode: () => recovery,
        storageKey: storageKey);
    addTearDown(service.dispose);
    return service;
  }

  CompanionMemoryPermission grant(CompanionMemoryUse use) =>
      memory.authorize(use, directUserGesture: true);

  Future<void> seed([String value = 'Synthetic companion note']) async {
    final permission = grant(CompanionMemoryUse.remember);
    await memory.remember(permission, value);
    permission.revoke();
  }

  static Future<CompanionMemoryFixture> create() async {
    final disk = await DataWipeFixture.create();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    await MemoryCrypto.clearDeviceKey();
    MemoryCrypto.resumeAfterDataWipe();
    EncryptedMemoryDurableScopedAdapter.debugResetStorageRegistryForTesting();
    final crypto = PausedCompanionCrypto(await MemoryCrypto.demo());
    addTearDown(() async {
      crypto.release();
      await MemoryCrypto.clearDeviceKey();
      MemoryCrypto.resumeAfterDataWipe();
      EncryptedMemoryDurableScopedAdapter.debugResetStorageRegistryForTesting();
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
    });
    return CompanionMemoryFixture._(disk, crypto);
  }
}

class PausedCompanionCrypto implements EncryptedMemoryDurableCrypto {
  PausedCompanionCrypto(MemoryCrypto crypto)
      : _inner = MemoryCryptoDurableAdapter(crypto);
  final MemoryCryptoDurableAdapter _inner;
  int decryptions = 0;
  int encryptions = 0;
  bool pauseRead = false;
  bool pauseWrite = false;
  final entered = Completer<void>();
  final decrypted = Completer<void>();
  final _release = Completer<void>();
  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  Future<void> _pause(bool pause) async {
    if (!pause) return;
    if (!entered.isCompleted) entered.complete();
    await _release.future;
  }

  @override
  Object get authorityToken => _inner.authorityToken;
  @override
  Future<Map<String, dynamic>> decryptJson(String blob) async {
    decryptions++;
    await _pause(pauseRead);
    final clear = await _inner.decryptJson(blob);
    if (!decrypted.isCompleted) decrypted.complete();
    return clear;
  }

  @override
  Future<String> encryptJson(Map<String, dynamic> json) async {
    encryptions++;
    await _pause(pauseWrite);
    return _inner.encryptJson(json);
  }
}
