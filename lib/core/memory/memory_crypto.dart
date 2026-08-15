import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../startup/neura_prefs_cache.dart';

/// App-layer encryption (AES-GCM) so memory is encrypted at rest even in plain SQLite.
class MemoryCrypto {
  static const _legacyKeySeed = 'neura.memoryGraph.seed.v1';
  static const _secureKeySeed = 'neura.memoryGraph.seed.v2';
  static const _secureKeyMarker = 'neura.memoryGraph.seed.secure.v2';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static MemoryCrypto? _shared;
  static Future<MemoryCrypto>? _loadFuture;
  static int _generation = 0;
  static bool _suspended = false;

  SecretKey? _key;
  int _generationAtCreation;
  final AesGcm _algo = AesGcm.with256bits();

  MemoryCrypto._(this._key) : _generationAtCreation = _generation;

  /// Removes the OS-backed encryption seed during a user-requested full wipe.
  /// Remaining encrypted blobs become unreadable even if a platform leaves a
  /// stale file behind.
  static Future<void> clearDeviceKey() async {
    final loading = _loadFuture;
    _suspended = true;
    _invalidateInMemory();
    try {
      if (loading != null) {
        try {
          await loading;
        } catch (_) {
          // Continue to a verified deletion even if loading failed.
        }
      }
      final sp = NeuraPrefsCache.prefs;
      await _secureStorage.delete(key: _secureKeySeed);
      final remaining =
          (await _secureStorage.read(key: _secureKeySeed))?.trim();
      if (remaining != null && remaining.isNotEmpty) {
        throw StateError('The OS-backed memory key could not be deleted.');
      }
      await sp.remove(_secureKeyMarker);
      await sp.remove(_legacyKeySeed);
      if (sp.containsKey(_secureKeyMarker) || sp.containsKey(_legacyKeySeed)) {
        throw StateError('The local memory-key metadata could not be cleared.');
      }
    } finally {
      // Even a partially failed wipe must revoke every cached key in this
      // process. Reload remains suspended until the complete wipe succeeds.
      _shared?._key = null;
      _shared = null;
      _loadFuture = null;
    }
  }

  /// Re-enables lazy creation of a fresh key after every other local-data
  /// deletion has completed successfully.
  static void resumeAfterDataWipe() {
    _suspended = false;
  }

  /// Loads this device's random key from the operating-system credential
  /// store. Existing preference-backed keys are migrated only after a verified
  /// secure write, so an interrupted migration cannot lock old data.
  static Future<MemoryCrypto> demo() {
    if (_suspended) {
      return Future<MemoryCrypto>.error(
        StateError('Memory encryption is suspended during local-data wipe.'),
      );
    }
    final shared = _shared;
    if (shared != null &&
        shared._key != null &&
        shared._generationAtCreation == _generation) {
      return Future.value(shared);
    }
    final loading = _loadFuture;
    if (loading != null) return loading;

    late final Future<MemoryCrypto> tracked;
    tracked = _load().then((crypto) {
      if (_suspended) {
        crypto._key = null;
        throw StateError('Memory encryption was suspended while loading.');
      }
      _shared = crypto;
      return crypto;
    }).whenComplete(() {
      if (identical(_loadFuture, tracked)) _loadFuture = null;
    });
    _loadFuture = tracked;
    return tracked;
  }

  static Future<MemoryCrypto> _load() async {
    final sp = NeuraPrefsCache.prefs;
    final expectsSecureKey = sp.getBool(_secureKeyMarker) == true;
    String? secureSeed;
    try {
      secureSeed =
          (await _secureStorage.read(key: _secureKeySeed))?.trim();
    } catch (_) {
      if (expectsSecureKey) {
        throw StateError(
          'The OS credential store is unavailable; refusing to replace the '
          'existing memory key.',
        );
      }
    }

    final legacySeed = sp.getString(_legacyKeySeed)?.trim();
    String? seed;
    if (expectsSecureKey) {
      if (secureSeed == null || secureSeed.isEmpty) {
        throw StateError(
          'The secure memory key is missing; refusing to generate a key that '
          'would make existing encrypted records unreadable.',
        );
      }
      seed = secureSeed;
    } else if (legacySeed != null && legacySeed.isNotEmpty) {
      // The marker is the migration commit point. Until it exists, the legacy
      // seed remains authoritative even if a stale/mismatched secure value is
      // present from an interrupted write.
      seed = legacySeed;
      try {
        if (secureSeed != legacySeed) {
          await _secureStorage.write(key: _secureKeySeed, value: legacySeed);
        }
        final verified =
            (await _secureStorage.read(key: _secureKeySeed))?.trim();
        if (verified == legacySeed) {
          await sp.setBool(_secureKeyMarker, true);
          await sp.remove(_legacyKeySeed);
        }
      } catch (_) {
        // Keep the authoritative preference-backed seed until a future retry.
      }
    } else if (secureSeed != null && secureSeed.isNotEmpty) {
      // A verified secure write may have completed just before its marker.
      seed = secureSeed;
      await sp.setBool(_secureKeyMarker, true);
      await sp.remove(_legacyKeySeed);
    } else {
      final bytes = Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      seed = base64UrlEncode(bytes);
      final seedToPersist = seed;
      try {
        await _secureStorage.write(
          key: _secureKeySeed,
          value: seedToPersist,
        );
        final verified =
            (await _secureStorage.read(key: _secureKeySeed))?.trim();
        if (verified == seedToPersist) {
          await sp.setBool(_secureKeyMarker, true);
          await sp.remove(_legacyKeySeed);
        } else {
          await _secureStorage.delete(key: _secureKeySeed);
          throw StateError(
            'The OS credential store could not verify the memory key.',
          );
        }
      } catch (error, stackTrace) {
        // A new installation has no legacy ciphertext to preserve. Fail
        // closed instead of placing a new encryption key beside its data in
        // SharedPreferences and calling that encrypted at rest.
        await sp.remove(_legacyKeySeed);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    final encodedSeed = seed;
    if (encodedSeed == null || encodedSeed.isEmpty) {
      throw StateError('No Neura memory key is available.');
    }
    final decoded = base64Url.decode(encodedSeed);
    if (decoded.length != 32) {
      throw const FormatException('Invalid Neura memory key length.');
    }
    return MemoryCrypto._(SecretKey(decoded));
  }

  Future<String> encryptJson(Map<String, dynamic> json) async {
    final key = await _activeKey();
    final generation = _generation;
    final nonce = _algo.newNonce();
    final clear = utf8.encode(jsonEncode(json));
    final secretBox = await _algo.encrypt(clear, secretKey: key, nonce: nonce);
    _ensureGeneration(generation);

    final blob = {
      'n': base64Encode(nonce),
      'c': base64Encode(secretBox.cipherText),
      'm': base64Encode(secretBox.mac.bytes),
    };
    return jsonEncode(blob);
  }

  Future<Map<String, dynamic>> decryptJson(String blob) async {
    final key = await _activeKey();
    final generation = _generation;
    final m = jsonDecode(blob) as Map<String, dynamic>;
    final nonce = base64Decode(m['n'] as String);
    final cipher = base64Decode(m['c'] as String);
    final macBytes = base64Decode(m['m'] as String);

    final box = SecretBox(cipher, nonce: nonce, mac: Mac(macBytes));
    final clear = await _algo.decrypt(box, secretKey: key);
    _ensureGeneration(generation);
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
    final key = await _activeKey();
    final generation = _generation;
    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(clear, secretKey: key, nonce: nonce);
    _ensureGeneration(generation);

    final out = BytesBuilder(copy: false);
    out.add(_magic);
    out.add([_version]);
    out.add(nonce);
    out.add(secretBox.mac.bytes);
    out.add(secretBox.cipherText);
    return out.toBytes();
  }

  Future<Uint8List> decryptBytes(Uint8List blob) async {
    final key = await _activeKey();
    final generation = _generation;
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
    final clear = await _algo.decrypt(box, secretKey: key);
    _ensureGeneration(generation);
    return Uint8List.fromList(clear);
  }

  Future<SecretKey> _activeKey() async {
    final key = _key;
    if (key != null && _generationAtCreation == _generation) return key;
    final refreshed = await MemoryCrypto.demo();
    final freshKey = refreshed._key;
    if (freshKey == null) {
      throw StateError('No active Neura memory key is available.');
    }
    _key = freshKey;
    _generationAtCreation = _generation;
    return freshKey;
  }

  void _ensureGeneration(int generation) {
    if (generation != _generation) {
      throw StateError('The memory key was invalidated during this operation.');
    }
  }

  static void _invalidateInMemory() {
    _generation += 1;
    _shared?._key = null;
    _shared = null;
    _loadFuture = null;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
