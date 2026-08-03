import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

import '../../startup/neura_prefs_cache.dart';

/// App-layer encryption (AES-GCM) so memory is encrypted at rest even in plain SQLite.
class MemoryCrypto {
  static const _keySeed = 'neura.memoryGraph.seed.v1';

  final SecretKey _key;
  final AesGcm _algo = AesGcm.with256bits();

  MemoryCrypto._(this._key);

  /// Loads this device's random key, generating and persisting one on first
  /// use. Previously this used a hardcoded, deterministic key baked into
  /// source (public on GitHub) — every install shared the same "encrypted at
  /// rest" key, which is not actually confidential. Mirrors the same
  /// random-seed-in-prefs approach as `MemoryVaultStore._getOrCreateSeed`.
  static Future<MemoryCrypto> demo() async {
    final sp = NeuraPrefsCache.prefs;
    var seed = sp.getString(_keySeed);
    if (seed == null || seed.trim().isEmpty) {
      final bytes = Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      seed = base64UrlEncode(bytes);
      await sp.setString(_keySeed, seed);
    }
    return MemoryCrypto._(SecretKey(base64Url.decode(seed)));
  }

  Future<String> encryptJson(Map<String, dynamic> json) async {
    final nonce = _algo.newNonce();
    final clear = utf8.encode(jsonEncode(json));
    final secretBox = await _algo.encrypt(clear, secretKey: _key, nonce: nonce);

    final blob = {
      'n': base64Encode(nonce),
      'c': base64Encode(secretBox.cipherText),
      'm': base64Encode(secretBox.mac.bytes),
    };
    return jsonEncode(blob);
  }

  Future<Map<String, dynamic>> decryptJson(String blob) async {
    final m = jsonDecode(blob) as Map<String, dynamic>;
    final nonce = base64Decode(m['n'] as String);
    final cipher = base64Decode(m['c'] as String);
    final macBytes = base64Decode(m['m'] as String);

    final box = SecretBox(cipher, nonce: nonce, mac: Mac(macBytes));
    final clear = await _algo.decrypt(box, secretKey: _key);
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }
}
