import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// App-layer encryption (AES-GCM) so memory is encrypted at rest even in plain SQLite.
/// In production, store the key in platform secure storage / user passphrase.
class MemoryCrypto {
  final SecretKey _key;
  final AesGcm _algo = AesGcm.with256bits();

  MemoryCrypto._(this._key);

  static Future<MemoryCrypto> demo() async {
    // Deterministic demo key (DO NOT ship). Replace with secure storage.
    final bytes = Uint8List.fromList(List<int>.generate(32, (i) => (i * 31) & 0xFF));
    return MemoryCrypto._(SecretKey(bytes));
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
