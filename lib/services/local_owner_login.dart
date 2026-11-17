import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'neura_secure_storage.dart';

/// An installation-local startup credential, independent of vault and cloud
/// credentials. A null record alone means that no owner password is configured.
class LocalOwnerLogin {
  static const storageKey = 'neura.owner.login.v1';
  static const setupDismissedKey = 'neura.owner.setup.dismissed.v1';
  static final instance = LocalOwnerLogin();
  Future<void> _pending = Future<void>.value();
  bool _suspended = false;

  Future<T> _run<T>(Future<T> Function() operation) {
    final result = _pending.then((_) async {
      if (_suspended) throw StateError('Owner login is unavailable.');
      final value = await operation();
      if (_suspended) throw StateError('Owner login is unavailable.');
      return value;
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<({List<int> salt, List<int> hash, bool remembered})?> _read() async {
    final raw = await neuraSecureStorage.read(key: storageKey);
    if (raw == null) return null;
    final record = jsonDecode(raw) as Map<String, dynamic>;
    final salt = base64Decode(record['salt'] as String);
    final hash = base64Decode(record['hash'] as String);
    if (salt.length != 16 || hash.length != 32) {
      throw const FormatException('Invalid owner login record.');
    }
    return (salt: salt, hash: hash, remembered: record['remembered'] as bool);
  }

  Future<void> _write(List<int> salt, List<int> hash, bool remember) async {
    final raw = jsonEncode({
      'salt': base64Encode(salt),
      'hash': base64Encode(hash),
      'remembered': remember,
    });
    await neuraSecureStorage.write(key: storageKey, value: raw);
    if (await neuraSecureStorage.read(key: storageKey) != raw) {
      throw StateError('Owner login could not be saved.');
    }
  }

  static Future<List<int>> _derive(
      ({String password, List<int> salt}) input) async {
    final kdf =
        Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256);
    final key = await kdf.deriveKeyFromPassword(
        password: input.password, nonce: input.salt);
    return key.extractBytes();
  }

  Future<bool?> remembered() => _run(() async => (await _read())?.remembered);

  Future<void> create(String password, {required bool remember}) =>
      _run(() async {
        if (password.trim().length < 12) {
          throw const FormatException('Use at least 12 characters.');
        }
        if (await _read() != null) {
          throw StateError('Owner password already exists.');
        }
        final random = Random.secure();
        final salt = List.generate(16, (_) => random.nextInt(256));
        await _write(salt,
            await compute(_derive, (password: password, salt: salt)), remember);
      });

  Future<bool> _matches(String password, List<int> salt, List<int> hash) async {
    final derived = await compute(_derive, (password: password, salt: salt));
    var difference = 0;
    for (var i = 0; i < hash.length; i++) {
      difference |= hash[i] ^ derived[i];
    }
    return difference == 0;
  }

  Future<bool> unlock(String password, {required bool remember}) =>
      _run(() async {
        final record = await _read();
        if (record == null ||
            !await _matches(password, record.salt, record.hash)) {
          return false;
        }
        if (remember != record.remembered) {
          await _write(record.salt, record.hash, remember);
        }
        return true;
      });

  Future<bool> remove(String password) => _run(() async {
        final record = await _read();
        if (record == null ||
            !await _matches(password, record.salt, record.hash)) {
          return false;
        }
        await _delete();
        return true;
      });

  Future<bool> unlockRemembered(Future<bool> Function() verifyDevice) => _run(
      () async => (await _read())?.remembered == true && await verifyDevice());

  Future<void> clearForDataWipe() async {
    _suspended = true;
    await _pending;
    await _delete();
  }

  Future<void> _delete() async {
    await neuraSecureStorage.delete(key: storageKey);
    if (await neuraSecureStorage.read(key: storageKey) != null) {
      throw StateError('Owner login deletion could not be verified.');
    }
  }
}
