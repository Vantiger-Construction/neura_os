import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cry;
import 'package:shared_preferences/shared_preferences.dart';

/// AES-256-GCM encryptor for memory content.
///
/// A 256-bit key is generated on first use and persisted in SharedPreferences
/// under [_keyPref].  Ciphertext is returned as a single base-64 string that
/// encodes [nonce | mac | ciphertext] so it can be stored as plain text.
///
/// Usage:
/// ```dart
/// final enc = MemoryEncryptor();
/// await enc.init();
/// final cipher = await enc.encrypt('hello');
/// final plain  = await enc.decrypt(cipher);
/// ```
class MemoryEncryptor {
  static const String _keyPref = 'neura_mem_enc_key_v1';

  static final _aesGcm = cry.AesGcm.with256bits();

  late cry.SecretKey _secretKey;
  bool _ready = false;

  /// Loads (or generates) the persisted encryption key.
  Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyPref);
    if (stored != null) {
      final keyBytes = base64Decode(stored);
      _secretKey = cry.SecretKey(keyBytes);
    } else {
      _secretKey = await _aesGcm.newSecretKey();
      final keyBytes = await _secretKey.extractBytes();
      await prefs.setString(_keyPref, base64Encode(keyBytes));
    }
    _ready = true;
  }

  /// Encrypts [plainText] and returns a base-64 encoded [nonce|mac|ciphertext].
  Future<String> encrypt(String plainText) async {
    assert(_ready, 'Call init() before encrypt()');
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: _secretKey,
      nonce: nonce,
    );
    // Pack: 12 B nonce + 16 B mac + n B ciphertext.
    final packed = Uint8List(
      secretBox.nonce.length +
          secretBox.mac.bytes.length +
          secretBox.cipherText.length,
    );
    var offset = 0;
    packed.setAll(offset, secretBox.nonce);
    offset += secretBox.nonce.length;
    packed.setAll(offset, secretBox.mac.bytes);
    offset += secretBox.mac.bytes.length;
    packed.setAll(offset, secretBox.cipherText);
    return base64Encode(packed);
  }

  /// Decrypts a base-64 string produced by [encrypt].
  ///
  /// Returns [encoded] unchanged if decryption fails (graceful degradation).
  Future<String> decrypt(String encoded) async {
    assert(_ready, 'Call init() before decrypt()');
    try {
      final packed = base64Decode(encoded);
      const nonceLen = 12;
      const macLen = 16;
      final nonce = packed.sublist(0, nonceLen);
      final mac = cry.Mac(packed.sublist(nonceLen, nonceLen + macLen));
      final cipherText = packed.sublist(nonceLen + macLen);
      final secretBox = cry.SecretBox(cipherText, nonce: nonce, mac: mac);
      final plain = await _aesGcm.decrypt(secretBox, secretKey: _secretKey);
      return utf8.decode(plain);
    } catch (_) {
      return encoded;
    }
  }
}
