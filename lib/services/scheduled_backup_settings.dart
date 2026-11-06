import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'neura_secure_storage.dart';

import 'neura_provider_credentials.dart' show NeuraCredentialStorage;
import '../startup/neura_prefs_cache.dart';

class _SecureScheduledBackupStorage implements NeuraCredentialStorage {
  const _SecureScheduledBackupStorage();

  static const FlutterSecureStorage _storage = neuraSecureStorage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

enum ScheduledBackupOutcome { success, failed }

/// Local, non-content settings for automatic encrypted vault backups.
///
/// The backup passphrase is the one sensitive value here, and it lives only
/// in OS secure storage, never SharedPreferences. It is always supplied by
/// the user once when they turn this on -- never auto-generated, since a
/// passphrase the user never saw is one they could never use to restore.
class ScheduledBackupSettings {
  ScheduledBackupSettings._({NeuraCredentialStorage? storage})
      : _storage = storage ?? const _SecureScheduledBackupStorage();

  static final ScheduledBackupSettings instance = ScheduledBackupSettings._();

  /// Creates an isolated instance backed by a fake [storage] for tests.
  /// Production code must use [instance].
  @visibleForTesting
  factory ScheduledBackupSettings.forTesting({
    required NeuraCredentialStorage storage,
  }) =>
      ScheduledBackupSettings._(storage: storage);

  static const _keyPassphrase = 'neura.scheduled_backup.passphrase.v1';
  static const _keyEnabled = 'neura.scheduled_backup.enabled';
  static const _keyLastRunAt = 'neura.scheduled_backup.last_run_at';
  static const _keyLastOutcome = 'neura.scheduled_backup.last_outcome';
  static const _keyLastError = 'neura.scheduled_backup.last_error';
  static const _keyRemovalPending =
      'neura.scheduled_backup.passphrase_removal_pending';

  final NeuraCredentialStorage _storage;

  static bool _suspendedForWipe = false;
  static Future<void> _mutationTail = Future<void>.value();
  static int _pendingMutations = 0;

  static void suspendForDataWipe() => _suspendedForWipe = true;

  static Future<void> drainForDataWipe() =>
      _mutationTail.timeout(const Duration(seconds: 30));

  @visibleForTesting
  static void resetWipeGateForTesting() {
    if (_pendingMutations != 0) {
      throw StateError('Backup settings are still being written.');
    }
    _suspendedForWipe = false;
  }

  static void _checkMutation() {
    if (_suspendedForWipe) {
      throw StateError('Backup settings are unavailable during data wipe.');
    }
  }

  Future<void> _mutate(Future<void> Function() operation) {
    if (_suspendedForWipe) {
      return Future.error(StateError('Data wipe started.'));
    }
    _pendingMutations++;
    final result = _mutationTail.then((_) async {
      _checkMutation();
      await operation();
    });
    _mutationTail = result
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pendingMutations--);
    return result;
  }

  bool get enabled =>
      (NeuraPrefsCache.prefsOrNull?.getBool(_keyEnabled) ?? false) &&
      !passphraseRemovalPending;

  bool get passphraseRemovalPending =>
      NeuraPrefsCache.prefsOrNull?.getBool(_keyRemovalPending) ?? false;

  Future<void> enable(String passphrase) => _mutate(() async {
        await _storage.write(key: _keyPassphrase, value: passphrase);
        _checkMutation();
        await _writeFlag(_keyEnabled, true);
        await _writeFlag(_keyRemovalPending, false);
      });

  Future<void> disable() => _mutate(() async {
        await _writeFlag(_keyRemovalPending, true);
        await _writeFlag(_keyEnabled, false);
        _checkMutation();
        await _storage.delete(key: _keyPassphrase);
        if ((await _storage.read(key: _keyPassphrase) ?? '').isNotEmpty) {
          throw StateError(
              'Backups are off, but passphrase removal needs retry.');
        }
        await _writeFlag(_keyRemovalPending, false);
      });

  Future<void> _writeFlag(String key, bool value) async {
    _checkMutation();
    final prefs = NeuraPrefsCache.prefs;
    try {
      await prefs.setBool(key, value);
    } catch (_) {
      // Durable readback decides whether the flag was committed.
    }
    await prefs.reload();
    _checkMutation();
    if (prefs.getBool(key) != value) {
      throw StateError('Backup settings could not be confirmed.');
    }
  }

  Future<String?> passphrase() => _storage.read(key: _keyPassphrase);

  DateTime? get lastRunAt {
    final raw = NeuraPrefsCache.prefsOrNull?.getString(_keyLastRunAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  ScheduledBackupOutcome? get lastOutcome {
    switch (NeuraPrefsCache.prefsOrNull?.getString(_keyLastOutcome)) {
      case 'success':
        return ScheduledBackupOutcome.success;
      case 'failed':
        return ScheduledBackupOutcome.failed;
      default:
        return null;
    }
  }

  String? get lastError =>
      NeuraPrefsCache.prefsOrNull?.getString(_keyLastError);

  Future<void> recordOutcome({
    required DateTime at,
    required ScheduledBackupOutcome outcome,
    String? error,
  }) =>
      _mutate(() async {
        await _writeMetadata(_keyLastRunAt, at.toUtc().toIso8601String());
        await _writeMetadata(_keyLastOutcome, outcome.name);
        await _writeMetadata(_keyLastError, error);
      });

  Future<void> _writeMetadata(String key, String? value) async {
    _checkMutation();
    final prefs = NeuraPrefsCache.prefs;
    try {
      value == null
          ? await prefs.remove(key)
          : await prefs.setString(key, value);
    } catch (_) {
      // Verify durable state even when the platform reports a failure.
    }
    await prefs.reload();
    _checkMutation();
    if (prefs.getString(key) != value) {
      throw StateError('Backup status could not be saved.');
    }
  }

  Future<void> clearForDataWipe() async {
    suspendForDataWipe();
    await drainForDataWipe();
    final prefs = NeuraPrefsCache.prefs;
    var removed = true;
    for (final key in [
      _keyEnabled,
      _keyLastRunAt,
      _keyLastOutcome,
      _keyLastError,
      _keyRemovalPending
    ]) {
      if (!await prefs.remove(key)) removed = false;
    }
    await _storage.delete(key: _keyPassphrase);
    if ((await _storage.read(key: _keyPassphrase) ?? '').isNotEmpty) {
      throw StateError('The scheduled backup passphrase could not be deleted.');
    }
    await prefs.reload();
    if (!removed ||
        [
          _keyEnabled,
          _keyLastRunAt,
          _keyLastOutcome,
          _keyLastError,
          _keyRemovalPending
        ].any(prefs.containsKey)) {
      throw StateError('Scheduled backup settings deletion was not verified.');
    }
  }
}
