import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../startup/neura_prefs_cache.dart';

/// This device's own signing identity for the Trusted Devices pairing flow
/// (see lib/living_intelligence/device_continuity.dart). The private key
/// never leaves this device or gets displayed; only the public key's
/// fingerprint is ever shown or shared, for the user to compare by eye.
class NeuraDeviceIdentityService {
  NeuraDeviceIdentityService._();

  static final NeuraDeviceIdentityService instance =
      NeuraDeviceIdentityService._();

  static const _kDeviceIdKey = 'neura.device_identity.id';
  static const _kDisplayNameKey = 'neura.device_identity.display_name';
  static const _kPublicKeyKey = 'neura.device_identity.public_key';
  static const _kPrivateKeySecureKey = 'neura.device_identity.private_key.v1';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final _algorithm = Ed25519();

  String? _deviceId;
  String? _displayName;
  String? _fingerprint;
  Future<void>? _loadFuture;

  String get deviceId {
    final id = _deviceId;
    if (id == null) {
      throw StateError(
        'NeuraDeviceIdentityService used before ensureLoaded() completed.',
      );
    }
    return id;
  }

  String get displayName => _displayName ?? _defaultDisplayName();

  String get fingerprint {
    final value = _fingerprint;
    if (value == null) {
      throw StateError(
        'NeuraDeviceIdentityService used before ensureLoaded() completed.',
      );
    }
    return value;
  }

  Future<void> ensureLoaded() {
    final existing = _loadFuture;
    if (existing != null) return existing;
    final future = _load();
    _loadFuture = future;
    return future;
  }

  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _displayName = trimmed;
    try {
      await NeuraPrefsCache.prefs.setString(_kDisplayNameKey, trimmed);
    } catch (_) {
      // The new name still applies for this session even if saving fails.
    }
  }

  Future<void> _load() async {
    final prefs = NeuraPrefsCache.prefs;

    var deviceId = prefs.getString(_kDeviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _newDeviceId();
      await prefs.setString(_kDeviceIdKey, deviceId);
    }
    _deviceId = deviceId;
    _displayName = prefs.getString(_kDisplayNameKey);

    final storedPublicKey = prefs.getString(_kPublicKeyKey);
    final storedPrivateKey =
        await _secureStorage.read(key: _kPrivateKeySecureKey);

    List<int> publicKeyBytes;
    if (storedPublicKey != null &&
        storedPublicKey.isNotEmpty &&
        storedPrivateKey != null &&
        storedPrivateKey.isNotEmpty) {
      publicKeyBytes = base64Decode(storedPublicKey);
    } else {
      final keyPair = await _algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final encodedPrivateKey = base64Encode(privateKeyBytes);

      await _secureStorage.write(
        key: _kPrivateKeySecureKey,
        value: encodedPrivateKey,
      );
      final verified = await _secureStorage.read(key: _kPrivateKeySecureKey);
      if (verified != encodedPrivateKey) {
        throw StateError(
          'The OS credential store could not verify the device key.',
        );
      }

      publicKeyBytes = publicKey.bytes;
      await prefs.setString(_kPublicKeyKey, base64Encode(publicKeyBytes));
    }

    final digest = await Sha256().hash(publicKeyBytes);
    _fingerprint = _formatFingerprint(digest.bytes);
  }

  static String _newDeviceId() => base64UrlEncode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
      ).replaceAll('=', '');

  static String _formatFingerprint(List<int> digestBytes) {
    final hex = digestBytes
        .take(8)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4 > hex.length ? hex.length : i + 4));
    }
    return groups.join('-');
  }

  static String _defaultDisplayName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {
      // Falls through to a platform-name default below.
    }
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isLinux) return 'Linux PC';
    return 'This device';
  }
}
