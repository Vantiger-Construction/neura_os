import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../services/neura_secure_storage.dart';
import '../core/app_log.dart';
import 'memory_vault_models.dart';
import '../../services/vault_item_source.dart';
import '../../startup/neura_prefs_cache.dart';

class MemoryVaultStore implements VaultItemSource {
  MemoryVaultStore._()
      : _now = DateTime.now,
        _wipeTimeout = const Duration(seconds: 30);
  @visibleForTesting
  MemoryVaultStore.forTesting(
      {DateTime Function()? now,
      Duration wipeTimeout = const Duration(seconds: 30)})
      : _now = now ?? DateTime.now,
        _wipeTimeout = wipeTimeout;
  static final MemoryVaultStore instance = MemoryVaultStore._();
  final DateTime Function() _now;
  final Duration _wipeTimeout;

  // NOTE: We no longer store the PIN. We only store a verifier blob.
  // A PIN is requested once per app session and cached in memory.
  static const _keyPinLegacy = 'neura.vault.pin.v1';
  static const _keyPinVerifier = 'neura.vault.pinVerifier.v1';
  static const _keySeed = 'neura.vault.seed.v1';
  static const _keySeedSecure = 'neura.vault.seed.secure.v2';
  static const _keySeedSecureMarker = 'neura.vault.seed.secure.marker.v2';
  static const _keyData = 'neura.vault.data.v2';
  // Ciphertext-only rollback record. A PIN change is committed only when this
  // record has been durably removed after both replacement values verify.
  static const _keyPinChange = 'neura.vault.pinChange.v1';

  // Legacy v1 blob (XOR) is stored here. We transparently migrate it to v2.
  static const _keyDataLegacy = 'neura.vault.data.v1';
  static const FlutterSecureStorage _secureStorage = neuraSecureStorage;

  // Crypto / format constants
  static const int _kPbkdf2Iterations = 120000;
  static const int _kDerivedBits = 256;
  static const int _kSeedLengthBytes = 32;
  static const int _kVaultVersion = 2;

  static const _verifierPlain = '{"neura":"vault_ok"}';

  // Serialize seed creation/migration without adding a package dependency.
  Future<void> _seedMutexTail = Future<void>.value();

  Future<T> _protectSeed<T>(Future<T> Function() operation) {
    final previous = _seedMutexTail;
    final release = Completer<void>();
    _seedMutexTail = release.future;
    return previous.then((_) => operation()).whenComplete(release.complete);
  }

  // Every vault read/migration and read-modify-write shares this queue. A
  // screen-local busy flag cannot protect a second screen or a pending wipe.
  Future<void> _vaultTail = Future<void>.value();
  int _generation = 0;
  bool _suspendedForWipe = false;
  Future<void>? _wipeInFlight;
  void Function() _checkAccess = () {};

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final previous = _vaultTail;
    final release = Completer<void>();
    _vaultTail = release.future;
    return previous.then((_) => operation()).whenComplete(release.complete);
  }

  Future<T> _operate<T>(Future<T> Function() operation,
      {bool Function()? mayWrite}) {
    final generation = _generation;
    final admitted = !_suspendedForWipe && _wipeInFlight == null;
    void check() {
      if (!admitted ||
          _suspendedForWipe ||
          generation != _generation ||
          (mayWrite != null && !mayWrite())) {
        throw StateError('Vault operation ended. Unlock and review again.');
      }
    }

    return _enqueue(() async {
      check();
      _checkAccess = check;
      try {
        await NeuraPrefsCache.prefs.reload();
        check();
        await _recoverPinChange();
        return await operation();
      } finally {
        _checkAccess = () {};
      }
    });
  }

  /// Revoke admission before any asynchronous full-data-wipe shutdown work.
  /// This process must restart before it can create a new vault.
  void suspendForDataWipe() {
    _suspendedForWipe = true;
    _generation++;
    _clearKeyCache();
  }

  // Cache derived key per app session to avoid repeated PBKDF2 cost.
  SecretKey? _cachedKey;
  String? _cachedPinForKey;
  String? _cachedSeedForKey;

  Future<String> _getOrCreateSeed({bool allowCreate = true}) async {
    return await _protectSeed(() async {
      _checkAccess();
      final sp = NeuraPrefsCache.prefs;
      final expectsSecureSeed = sp.getBool(_keySeedSecureMarker) == true;
      String? secureSeed;
      try {
        secureSeed = (await _secureStorage.read(key: _keySeedSecure))?.trim();
      } catch (e, st) {
        await AppLog.instance.caught('vault_secure_seed_read_failed', e, st);
        throw StateError(
          'The OS credential store is unavailable; refusing to replace the '
          'existing vault key.',
        );
      }

      _checkAccess();
      if (expectsSecureSeed) {
        if (!_isValidSeed(secureSeed)) {
          throw StateError(
            'The secure vault key is missing or invalid; refusing to unlock '
            'existing vault data.',
          );
        }
        return secureSeed!;
      }

      final legacySeed = sp.getString(_keySeed)?.trim();
      if (_isValidSeed(legacySeed)) {
        try {
          await _secureStorage.write(key: _keySeedSecure, value: legacySeed!);
          final verified =
              (await _secureStorage.read(key: _keySeedSecure))?.trim();
          if (verified != legacySeed) {
            throw StateError('The secure vault key could not be verified.');
          }
          _checkAccess();
          await sp.setBool(_keySeedSecureMarker, true);
          await sp.remove(_keySeed);
          return verified!;
        } catch (e, st) {
          await AppLog.instance
              .caught('vault_secure_seed_migration_failed', e, st);
          throw StateError(
            'The OS credential store is unavailable; refusing to continue '
            'with an unprotected vault seed.',
          );
        }
      }

      // A secure write may have completed immediately before its marker.
      if (_isValidSeed(secureSeed)) {
        _checkAccess();
        await sp.setBool(_keySeedSecureMarker, true);
        await sp.remove(_keySeed);
        return secureSeed!;
      }

      if (!allowCreate) {
        throw StateError('The existing vault key is missing.');
      }
      _checkAccess();
      final bytes = List<int>.generate(
        _kSeedLengthBytes,
        (_) => Random.secure().nextInt(256),
      );
      final generated = base64UrlEncode(bytes);
      try {
        await _secureStorage.write(key: _keySeedSecure, value: generated);
        final verified =
            (await _secureStorage.read(key: _keySeedSecure))?.trim();
        if (verified != generated) {
          throw StateError('The secure vault key could not be verified.');
        }
        _checkAccess();
        await sp.setBool(_keySeedSecureMarker, true);
        await sp.remove(_keySeed);
        return verified!;
      } catch (e, st) {
        try {
          await _secureStorage.delete(key: _keySeedSecure);
        } catch (_) {
          // Preserve the original failure; the next attempt still fails closed.
        }
        await AppLog.instance.caught('vault_secure_seed_create_failed', e, st);
        Error.throwWithStackTrace(
          StateError('The OS credential store could not verify the vault key.'),
          st,
        );
      }
    });
  }

  static bool _isValidSeed(String? value) {
    if (value == null || value.isEmpty) return false;
    try {
      return base64Url.decode(value).length == _kSeedLengthBytes;
    } catch (_) {
      return false;
    }
  }

  Future<SecretKey> _deriveKeyRaw({
    required String pin,
    required String seed,
  }) async {
    // PBKDF2: derive a 256-bit key from the PIN with a per-device salt.
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _kPbkdf2Iterations,
      bits: _kDerivedBits,
    );
    final salt = utf8.encode('neura_vault::$seed');
    return pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
  }

  Future<SecretKey> _deriveKey({
    required String pin,
    required String seed,
  }) async {
    final trimmedPin = pin.trim();
    // Return cached key when pin and seed match the cache.
    if (_cachedKey != null &&
        _cachedPinForKey == trimmedPin &&
        _cachedSeedForKey == seed) {
      return _cachedKey!;
    }
    final key = await _deriveKeyRaw(pin: trimmedPin, seed: seed);
    _cachedKey = key;
    _cachedPinForKey = trimmedPin;
    _cachedSeedForKey = seed;
    return key;
  }

  void _clearKeyCache() {
    _cachedKey = null;
    _cachedPinForKey = null;
    _cachedSeedForKey = null;
  }

  Future<String> _encryptJson(String json, {required String pin}) async {
    final seed = await _getOrCreateSeed();
    final key = await _deriveKey(pin: pin, seed: seed);
    final alg = AesGcm.with256bits();

    _checkAccess();
    final nonce = alg.newNonce();
    final box = await alg.encrypt(
      utf8.encode(json),
      secretKey: key,
      nonce: nonce,
    );

    final payload = {
      'v': _kVaultVersion,
      'nonce': base64UrlEncode(box.nonce),
      'cipher': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    };
    return jsonEncode(payload);
  }

  Future<String?> _decryptJson(String blob, {required String pin}) async {
    // v2 JSON blob
    if (blob.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(blob);
        if (decoded is! Map) return null;
        final v = decoded['v'];
        if (v != _kVaultVersion) return null;
        final nonceB = base64Url.decode(decoded['nonce'] as String);
        final cipherB = base64Url.decode(decoded['cipher'] as String);
        final macB = base64Url.decode(decoded['mac'] as String);

        final seed = await _getOrCreateSeed(allowCreate: false);
        final key = await _deriveKey(pin: pin, seed: seed);
        final alg = AesGcm.with256bits();

        final box = SecretBox(
          Uint8List.fromList(cipherB),
          nonce: Uint8List.fromList(nonceB),
          mac: Mac(Uint8List.fromList(macB)),
        );

        final clear = await alg.decrypt(box, secretKey: key);
        return utf8.decode(clear);
      } catch (e, st) {
        await AppLog.instance.caught('vault_v2_decrypt_failed', e, st);
        return null;
      }
    }

    // v1 legacy: XOR obfuscation.
    try {
      final legacy = _deobfuscate(blob, pin);
      return legacy;
    } catch (e, st) {
      await AppLog.instance.caught('vault_legacy_decrypt_failed', e, st);
      return null;
    }
  }

  String _deobfuscate(String obf, String pin) {
    // Legacy XOR. Kept only for migration.
    final raw = base64Url.decode(obf);
    if (pin.trim().isEmpty) return utf8.decode(raw);
    final key = utf8.encode(pin);
    final out = List<int>.generate(
      raw.length,
      (i) => raw[i] ^ key[i % key.length],
    );
    return utf8.decode(out);
  }

  Future<void> _migrateLegacyPinIfNeeded() async {
    final sp = NeuraPrefsCache.prefs;
    final verifier = sp.getString(_keyPinVerifier);
    if (verifier != null && verifier.trim().isNotEmpty) return;

    final legacyPin = sp.getString(_keyPinLegacy);
    if (legacyPin != null && legacyPin.trim().isNotEmpty) {
      await _configurePin(legacyPin.trim());
      await sp.remove(_keyPinLegacy);
      await AppLog.instance.info('vault_event', {
        'msg': 'Vault PIN migrated to verifier (no PIN stored).',
      });
    }
  }

  Future<bool> hasPinConfigured() => _operate(_hasPinConfigured);

  Future<bool> _hasPinConfigured() async {
    await _migrateLegacyPinIfNeeded();
    final sp = NeuraPrefsCache.prefs;
    final verifier = sp.getString(_keyPinVerifier);
    return verifier != null && verifier.trim().isNotEmpty;
  }

  Future<void> configurePin(String pin) => _operate(() => _configurePin(pin));

  Future<void> _configurePin(String pin) async {
    final enc = await _encryptJson(_verifierPlain, pin: pin.trim());
    _checkAccess();
    await _writeString(_keyPinVerifier, enc);
  }

  Future<void> _writeString(String key, String? value) async {
    _checkAccess();
    final sp = NeuraPrefsCache.prefs;
    final ok =
        value == null ? await sp.remove(key) : await sp.setString(key, value);
    // Platform failures can still mutate SharedPreferences' in-memory cache.
    await sp.reload();
    if (!ok || sp.getString(key) != value) {
      throw StateError('The vault write could not be confirmed.');
    }
  }

  Future<void> _recoverPinChange() async {
    final sp = NeuraPrefsCache.prefs;
    final pending = sp.getString(_keyPinChange);
    if (pending == null) return;
    final record = jsonDecode(pending);
    if (record is! Map ||
        record['version'] != 1 ||
        record['verifier'] is! String ||
        (record['verifier'] as String).isEmpty ||
        !record.containsKey('data') ||
        (record['data'] != null && record['data'] is! String)) {
      throw StateError('Vault PIN recovery requires the preserved backup.');
    }
    // Keep the rollback record until both old values are durable again. A
    // failed recovery leaves it available for the next unlock/restart.
    if (sp.getString(_keyData) != record['data']) {
      await _writeString(_keyData, record['data'] as String?);
    }
    if (sp.getString(_keyPinVerifier) != record['verifier']) {
      await _writeString(_keyPinVerifier, record['verifier'] as String);
    }
    await _writeString(_keyPinChange, null);
    _clearKeyCache();
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<bool> validatePin(String pin) => _operate(() => _validatePin(pin));

  Future<bool> _validatePin(String pin) async {
    await _migrateLegacyPinIfNeeded();
    final sp = NeuraPrefsCache.prefs;
    final verifier = sp.getString(_keyPinVerifier);
    if (verifier == null || verifier.trim().isEmpty) return false;
    final clear = await _decryptJson(verifier, pin: pin.trim());
    if (clear == null) return false;
    return _constantTimeEquals(
      Uint8List.fromList(utf8.encode(clear)),
      Uint8List.fromList(utf8.encode(_verifierPlain)),
    );
  }

  @override
  Future<List<VaultItem>> getItems({required String pin}) =>
      _operate(() => _readItems(pin: pin));

  Future<List<VaultItem>> _readItems({required String pin}) async {
    _checkAccess();
    final sp = NeuraPrefsCache.prefs;
    final blobV2 = sp.getString(_keyData);
    if (blobV2 != null) {
      if (blobV2.trim().isEmpty) throw StateError('The vault is unreadable.');
      final clear = await _decryptJson(blobV2, pin: pin);
      _checkAccess();
      if (clear == null) {
        throw StateError(
            'The vault could not be decrypted. Existing data was preserved.');
      }
      return decodeVaultItems(clear, strict: true);
    }
    final legacy = sp.getString(_keyDataLegacy);
    if (legacy != null) {
      final clear = await _decryptJson(legacy, pin: pin);
      _checkAccess();
      if (clear == null) throw StateError('The legacy vault is unreadable.');
      final items = decodeVaultItems(clear, strict: true);
      await _save(items, pin: pin);
      _checkAccess();
      await sp.remove(_keyDataLegacy);
      return items;
    }
    return <VaultItem>[];
  }

  Future<void> _save(List<VaultItem> items, {required String pin}) async {
    final json = encodeVaultItems(items);
    final enc = await _encryptJson(json, pin: pin);
    _checkAccess();
    await _writeString(_keyData, enc);
  }

  Future<void> add({
    required String pin,
    required String title,
    required String body,
    List<String> tags = const [],
  }) =>
      _operate(() async {
        final items = await _readItems(pin: pin);
        final now = _now();
        final baseId = 'v_${now.microsecondsSinceEpoch}';
        var id = baseId;
        var suffix = 0;
        final ids = items.map((item) => item.id).toSet();
        while (ids.contains(id)) {
          id = '${baseId}_${++suffix}';
        }
        items.add(
          VaultItem(
            id: id,
            createdAt: now,
            title: title,
            body: body,
            tags: tags,
          ),
        );
        await _save(items, pin: pin);
      });

  Future<void> delete({required String pin, required String id}) =>
      _operate(() async {
        final items = await _readItems(pin: pin);
        items.removeWhere((e) => e.id == id);
        await _save(items, pin: pin);
      });

  /// Re-encrypts vault data and verifier with a new PIN.
  /// Throws StateError if the oldPin is incorrect or migration fails.
  Future<void> changePin({
    required String oldPin,
    required String newPin,
  }) =>
      _operate(() async {
        final sp = NeuraPrefsCache.prefs;
        final oldPinTrim = oldPin.trim();
        final newPinTrim = newPin.trim();

        // Validate old PIN first
        final verifier = sp.getString(_keyPinVerifier);
        if (verifier == null || verifier.trim().isEmpty) {
          throw StateError('No PIN configured');
        }
        final clear = await _decryptJson(verifier, pin: oldPinTrim);
        if (clear == null) {
          throw StateError('Old PIN is incorrect');
        }

        // Decrypt items with old PIN and re-encrypt with new PIN.
        final items = await _readItems(pin: oldPinTrim);
        final encData =
            await _encryptJson(encodeVaultItems(items), pin: newPinTrim);
        final encVerifier = await _encryptJson(_verifierPlain, pin: newPinTrim);

        _checkAccess();
        await _writeString(
            _keyPinChange,
            jsonEncode({
              'version': 1,
              'data': sp.getString(_keyData),
              'verifier': verifier,
            }));
        try {
          await _writeString(_keyData, encData);
          await _writeString(_keyPinVerifier, encVerifier);
          await _writeString(_keyPinChange, null);
        } catch (_) {
          await _recoverPinChange();
          rethrow;
        } finally {
          _clearKeyCache();
        }
      });

  /// Atomically merges validated portable-backup items into the local vault.
  ///
  /// Identical items are skipped. If an imported item reuses an existing ID
  /// with different content, both copies are preserved under distinct IDs.
  @override
  Future<int> importItems({
    required String pin,
    required List<VaultItem> imported,
    bool Function()? mayWrite,
  }) =>
      _operate(() async {
        if (!await _validatePin(pin)) {
          throw StateError('Unlock the current vault before restoring.');
        }
        final current = await _readItems(pin: pin);
        final byId = <String, VaultItem>{
          for (final item in current) item.id: item,
        };
        var importedCount = 0;
        var collisionIndex = 0;

        for (final item in imported) {
          if (item.id.trim().isEmpty) {
            throw const FormatException('A backup entry has no identifier.');
          }
          final existing = byId[item.id];
          if (existing == null) {
            byId[item.id] = item;
            importedCount++;
            continue;
          }
          if (_sameItem(existing, item)) continue;

          String recoveredId;
          do {
            collisionIndex++;
            recoveredId = '${item.id}_recovered_$collisionIndex';
          } while (byId.containsKey(recoveredId));
          byId[recoveredId] = VaultItem(
            id: recoveredId,
            createdAt: item.createdAt,
            title: item.title,
            body: item.body,
            tags: item.tags,
          );
          importedCount++;
        }

        if (importedCount == 0) return 0;
        final merged = byId.values.toList()
          ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
        await _save(merged, pin: pin);
        return importedCount;
      }, mayWrite: mayWrite);

  bool _sameItem(VaultItem left, VaultItem right) {
    if (left.createdAt.toUtc() != right.createdAt.toUtc() ||
        left.title != right.title ||
        left.body != right.body ||
        left.tags.length != right.tags.length) {
      return false;
    }
    for (var i = 0; i < left.tags.length; i++) {
      if (left.tags[i] != right.tags[i]) return false;
    }
    return true;
  }

  Future<void> wipe() {
    final pending = _wipeInFlight;
    if (pending != null) return _waitForWipe(pending);
    _generation++;
    final wiping = _enqueue(_wipe);
    final completed = wiping.whenComplete(() => _wipeInFlight = null);
    _wipeInFlight = completed;
    return _waitForWipe(completed);
  }

  Future<void> _waitForWipe(Future<void> operation) =>
      operation.timeout(_wipeTimeout, onTimeout: () {
        // The underlying queue and closed admission remain in place. A late
        // platform write must drain into deletion, never become a new vault.
        throw StateError('Vault wipe is incomplete: storage has not responded. '
            'Keep the app open and retry; no deletion success was confirmed.');
      });

  Future<void> _wipe() async {
    final sp = NeuraPrefsCache.prefs;
    var removed = true;
    for (final key in [
      _keyData,
      _keyDataLegacy,
      _keyPinVerifier,
      _keyPinLegacy,
      _keyPinChange,
      _keySeedSecureMarker,
      _keySeed
    ]) {
      if (!await sp.remove(key)) removed = false;
    }
    await _secureStorage.delete(key: _keySeedSecure);
    final remaining = (await _secureStorage.read(key: _keySeedSecure))?.trim();
    if (remaining != null && remaining.isNotEmpty) {
      throw StateError('The secure vault key could not be deleted.');
    }
    // Clear cached key too
    _clearKeyCache();
    await sp.reload();
    if (!removed ||
        sp.containsKey(_keyPinChange) ||
        sp.containsKey(_keyPinLegacy) ||
        sp.containsKey(_keySeedSecureMarker) ||
        sp.containsKey(_keySeed) ||
        sp.containsKey(_keyPinVerifier) ||
        sp.containsKey(_keyData) ||
        sp.containsKey(_keyDataLegacy)) {
      throw StateError('Vault deletion could not be verified.');
    }
  }
}
