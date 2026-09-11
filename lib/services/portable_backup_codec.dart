import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Versioned, device-independent encrypted backup envelope.
///
/// Unlike Neura's at-rest vault encryption, this format derives its key only
/// from the user's export passphrase and a random salt stored in the envelope.
/// It can therefore be restored on another installation without copying any
/// device credential-store secrets.
class PortableBackupCodec {
  PortableBackupCodec({
    Random? random,
    int iterations = 210000,
  })  : _random = random ?? Random.secure(),
        _iterations = iterations;

  static const format = 'neura-portable-backup';
  static const version = 1;
  static const _saltLength = 16;
  static const _keyBits = 256;

  final Random _random;
  final int _iterations;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<String> encrypt({
    required Map<String, dynamic> payload,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => _random.nextInt(256)),
    );
    final key = await _deriveKey(passphrase, salt);
    final clear = utf8.encode(jsonEncode(payload));
    final box = await _cipher.encrypt(clear, secretKey: key);

    return jsonEncode({
      'format': format,
      'version': version,
      'kdf': {
        'name': 'pbkdf2-hmac-sha256',
        'iterations': _iterations,
        'salt': base64UrlEncode(salt),
      },
      'cipher': {
        'name': 'aes-256-gcm',
        'nonce': base64UrlEncode(box.nonce),
        'mac': base64UrlEncode(box.mac.bytes),
        'data': base64UrlEncode(box.cipherText),
      },
    });
  }

  Future<Map<String, dynamic>> decrypt({
    required String envelope,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    final decoded = jsonDecode(envelope);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['version'] != version) {
      throw const FormatException('Unsupported Neura backup format.');
    }

    final kdf = (decoded['kdf'] as Map).cast<String, dynamic>();
    final cipher = (decoded['cipher'] as Map).cast<String, dynamic>();
    if (kdf['name'] != 'pbkdf2-hmac-sha256' ||
        cipher['name'] != 'aes-256-gcm') {
      throw const FormatException('Unsupported Neura backup cryptography.');
    }

    final iterations = kdf['iterations'] as int;
    if (iterations < 120000 || iterations > 1000000) {
      throw const FormatException('Unsafe backup key-derivation parameters.');
    }
    final salt = base64Url.decode(kdf['salt'] as String);
    if (salt.length != _saltLength) {
      throw const FormatException('Invalid Neura backup salt.');
    }

    final key = await _deriveKey(passphrase, salt, iterations: iterations);
    final box = SecretBox(
      base64Url.decode(cipher['data'] as String),
      nonce: base64Url.decode(cipher['nonce'] as String),
      mac: Mac(base64Url.decode(cipher['mac'] as String)),
    );
    final clear = await _cipher.decrypt(box, secretKey: key);
    final payload = jsonDecode(utf8.decode(clear));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid Neura backup payload.');
    }
    return payload;
  }

  Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt, {
    int? iterations,
  }) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations ?? _iterations,
      bits: _keyBits,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  void _validatePassphrase(String passphrase) {
    if (passphrase.length < 12) {
      throw ArgumentError.value(
        passphrase,
        'passphrase',
        'Use at least 12 characters for a portable backup.',
      );
    }
  }
}
