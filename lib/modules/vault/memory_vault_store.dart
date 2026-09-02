import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mutex/mutex.dart';
import '../core/app_log.dart';
import 'memory_vault_models.dart';
import '../../startup/neura_prefs_cache.dart';

class MemoryVaultStore {
  MemoryVaultStore._();
  static final MemoryVaultStore instance = MemoryVaultStore._();

  // NOTE: We no longer store the PIN. We only store a verifier blob.
  // A PIN is requested once per app session and cached in memory.
  static const _keyPinLegacy = 'neura.vault.pin.v1';
  static const _keyPinVerifier = 'neura.vault.pinVerifier.v1';
  static const _keySeed = 'neura.vault.seed.v1';
  static const _keySeedSecure = 'neura.vault.seed.secure.v2';
  static const _keySeedSecureMarker = 'neura.vault.seed.secure.marker.v2';
  static const _keyData = 'neura.vault.data.v2';

  // Legacy v1 blob (XOR) is stored here. We transparently migrate it to v2.
  static const _keyDataLegacy = 'neura.vault.data.v1';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Crypto / format constants
  static const int _kPbkdf2Iterations = 120000;
  static const int _kDerivedBits = 256;
  static const int _kSeedLengthBytes = 32;
  static const int _kVaultVersion = 2;

  static const _verifierPlain = '{"neura":"vault_ok"}';

  // Protect seed creation/migration against concurrent access.
  final Mutex _seedMutex = Mutex();

  // Cache derived key per app session to avoid repeated PBKDF2 cost.
  SecretKey? _cachedKey;
  String? _cachedPinForKey;
  String? _cachedSeedForKey;

  Future<String> _getOrCreateSeed() async {
    return await _seedMutex.protect(() async {
      final sp = NeuraPrefsCache.prefs;
      final expectsSecureSeed = sp.getBool(_keySeedSecureMarker) == true;
      String? secureSeed;
      try {
        secureSeed = (await _secureStorage.read(key: _keySeedSecure))?.trim();
      } catch (e, st) {
        await AppLog.instance.caught('vault_secure_seed_read_failed', e, st);
        if (expectsSecureSeed) {
          throw StateError(
            'The OS credential store is unavailable; refusing to replace the '
            'existing vault key.',
          );
        }
      }

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
        await sp.setBool(_keySeedSecureMarker, true);
        await sp.remove(_keySeed);
        return secureSeed!;
      }

      final bytes = List<int>.generate(
          _kSeedLengthBytes, (_) => Random.secure().nextInt(256));
      final generated = base64UrlEncode(bytes);
      try {
        await _secureStorage.write(key: _keySeedSecure, value: generated);
        final verified =
            (await _secureStorage.read(key: _keySeedSecure))?.trim();
        if (verified != generated) {
          throw StateError('The secure vault key could not be verified.');
        }
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

        final seed = await _getOrCreateSeed();
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
      await configurePin(legacyPin.trim());
      await sp.remove(_keyPinLegacy);
      await AppLog.instance.info('vault_event', {
        'msg': 'Vault PIN migrated to verifier (no PIN stored).',
      });
    }
  }

  Future<bool> hasPinConfigured() async {
    await _migrateLegacyPinIfNeeded();
    final sp = NeuraPrefsCache.prefs;
    final verifier = sp.getString(_keyPinVerifier);
    return verifier != null && verifier.trim().isNotEmpty;
  }

  Future<void> configurePin(String pin) async {
    final sp = NeuraPrefsCache.prefs;
    final enc = await _encryptJson(_verifierPlain, pin: pin.trim());
    await sp.setString(_keyPinVerifier, enc);
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<bool> validatePin(String pin) async {
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

  Future<List<VaultItem>> getItems({required String pin}) async {
    try {
      final sp = NeuraPrefsCache.prefs;

      // Prefer v2.
      final blobV2 = sp.getString(_keyData);
      if (blobV2 != null && blobV2.trim().isNotEmpty) {
        final clear = await _decryptJson(blobV2, pin: pin);
        if (clear == null) return <VaultItem>[];
        return decodeVaultItems(clear);
      }

      // Legacy v1: migrate if present.
      final legacy = sp.getString(_keyDataLegacy);
      if (legacy != null && legacy.trim().isNotEmpty) {
        final clear = await _decryptJson(legacy, pin: pin);
        final items =
            clear == null ? <VaultItem>[] : decodeVaultItems(clear);
        // Migrate to v2.
        final enc = await _encryptJson(encodeVaultItems(items), pin: pin);
        await sp.setString(_keyData, enc);
        await sp.remove(_keyDataLegacy);
        await AppLog.instance
            .info('vault_event', {'msg': 'Vault migrated to AES-GCM (v2).'});
        return items;
      }

      return <VaultItem>[];
    } catch (e, st) {
      await AppLog.instance.caught('vault_items_read_failed', e, st);
      return <VaultItem>[];
    }
  }

  Future<void> _save(List<VaultItem> items, {required String pin}) async {
    final sp = NeuraPrefsCache.prefs;
    final json = encodeVaultItems(items);
    final enc = await _encryptJson(json, pin: pin);
    await sp.setString(_keyData, enc);
  }

  Future<void> add({
    required String pin,
    required String title,
    required String body,
    List<String> tags = const [],
  }) async {
    final items = await getItems(pin: pin);
    final id = 'v_${DateTime.now().millisecondsSinceEpoch}';
    items.add(
      VaultItem(
        id: id,
        createdAt: DateTime.now(),
        title: title,
        body: body,
        tags: tags,
      ),
    );
    await _save(items, pin: pin);
  }

  Future<void> delete({required String pin, required String id}) async {
    final items = await getItems(pin: pin);
    items.removeWhere((e) => e.id == id);
    await _save(items, pin: pin);
  }

  /// Re-encrypts vault data and verifier with a new PIN.
  /// Throws StateError if the oldPin is incorrect or migration fails.
  Future<void> changePin({
    required String oldPin,
    required String newPin,
  }) async {
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
    final items = await getItems(pin: oldPinTrim);
    final encData = await _encryptJson(encodeVaultItems(items), pin: newPinTrim);
    final encVerifier = await _encryptJson(_verifierPlain, pin: newPinTrim);

    // Persist atomically as much as possible
    await sp.setString(_keyData, encData);
    await sp.setString(_keyPinVerifier, encVerifier);

    // Clear cached key to avoid mismatch
    _clearKeyCache();
  }

  Future<void> wipe() async {
    final sp = NeuraPrefsCache.prefs;
    await sp.remove(_keyData);
    await sp.remove(_keyDataLegacy);
    await sp.remove(_keyPinVerifier);
    await _secureStorage.delete(key: _keySeedSecure);
    final remaining = (await _secureStorage.read(key: _keySeedSecure))?.trim();
    if (remaining != null && remaining.isNotEmpty) {
      throw StateError('The secure vault key could not be deleted.');
    }
    await sp.remove(_keySeedSecureMarker);
    await sp.remove(_keySeed);
    // Clear cached key too
    _clearKeyCache();
    if (sp.containsKey(_keySeedSecureMarker) ||
        sp.containsKey(_keySeed) ||
        sp.containsKey(_keyPinVerifier) ||
        sp.containsKey(_keyData) ||
        sp.containsKey(_keyDataLegacy)) {
      throw StateError('Vault deletion could not be verified.');
    }
  }
}
