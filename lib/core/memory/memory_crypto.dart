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

  // Raw-bytes variants for large binary payloads (e.g. recorded audio),
  // where JSON/base64 wrapping (as encryptJson/decryptJson use) would add
  // ~33%+ overhead for no benefit. Layout: 4-byte magic, 1-byte version,
  // 12-byte nonce, 16-byte MAC, then ciphertext -- no JSON, same key/algo.
  static final List<int> _magic = utf8.encode('NAE1');
  static const int _version = 1;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  Future<Uint8List> encryptBytes(Uint8List clear) async {
    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(clear, secretKey: _key, nonce: nonce);

    final out = BytesBuilder(copy: false);
    out.add(_magic);
    out.add([_version]);
    out.add(nonce);
    out.add(secretBox.mac.bytes);
    out.add(secretBox.cipherText);
    return out.toBytes();
  }

  Future<Uint8List> decryptBytes(Uint8List blob) async {
    final headerLen = _magic.length + 1 + _nonceLength + _macLength;
    if (blob.length < headerLen) {
      throw const FormatException('Encrypted blob too short.');
    }
    var offset = 0;
    final magic = blob.sublist(offset, offset + _magic.length);
    offset += _magic.length;
    if (!_bytesEqual(magic, _magic)) {
      throw const FormatException('Bad magic bytes.');
    }
    final version = blob[offset];
    offset += 1;
    if (version != _version) {
      throw FormatException('Unsupported version: $version');
    }
    final nonce = blob.sublist(offset, offset + _nonceLength);
    offset += _nonceLength;
    final mac = blob.sublist(offset, offset + _macLength);
    offset += _macLength;
    final cipherText = blob.sublist(offset);

    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    final clear = await _algo.decrypt(box, secretKey: _key);
    return Uint8List.fromList(clear);
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
