import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
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
  static const _keyData = 'neura.vault.data.v2';

  // Legacy v1 blob (XOR) is stored here. We transparently migrate it to v2.
  static const _keyDataLegacy = 'neura.vault.data.v1';

  static const _verifierPlain = '{"neura":"vault_ok"}';

  Future<String> _getOrCreateSeed() async {
    final sp = NeuraPrefsCache.prefs;
    var seed = sp.getString(_keySeed);
    if (seed != null && seed.trim().isNotEmpty) return seed;
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    seed = base64UrlEncode(bytes);
    await sp.setString(_keySeed, seed);
    return seed;
  }

  Future<SecretKey> _deriveKey(
      {required String pin, required String seed}) async {
    // PBKDF2: derive a 256-bit key from the PIN with a per-device salt.
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final salt = utf8.encode('neura_vault::$seed');
    return pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
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
      'v': 2,
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
        if (v != 2) return null;
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
    final out =
        List<int>.generate(raw.length, (i) => raw[i] ^ key[i % key.length]);
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
      await AppLog.instance.info('vault_event',
          {'msg': 'Vault PIN migrated to verifier (no PIN stored).'});
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

  Future<bool> validatePin(String pin) async {
    await _migrateLegacyPinIfNeeded();
    final sp = NeuraPrefsCache.prefs;
    final verifier = sp.getString(_keyPinVerifier);
    if (verifier == null || verifier.trim().isEmpty) return false;
    final clear = await _decryptJson(verifier, pin: pin.trim());
    return clear == _verifierPlain;
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
        final items = clear == null ? <VaultItem>[] : decodeVaultItems(clear);
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

  Future<void> add(
      {required String pin,
      required String title,
      required String body,
      List<String> tags = const []}) async {
    final items = await getItems(pin: pin);
    final id = 'v_${DateTime.now().millisecondsSinceEpoch}';
    items.add(VaultItem(
      id: id,
      createdAt: DateTime.now(),
      title: title,
      body: body,
      tags: tags,
    ));
    await _save(items, pin: pin);
  }

  Future<void> delete({required String pin, required String id}) async {
    final items = await getItems(pin: pin);
    items.removeWhere((e) => e.id == id);
    await _save(items, pin: pin);
  }

  Future<void> wipe() async {
    final sp = NeuraPrefsCache.prefs;
    await sp.remove(_keyData);
    await sp.remove(_keyDataLegacy);
    await sp.remove(_keyPinVerifier);
    // Keeping _keySeed is fine, but wiping it is also ok.
    // We'll keep it to avoid breaking older entries if the user reconfigures with the same PIN.
  }
}
