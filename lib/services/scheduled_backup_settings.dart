import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'neura_provider_credentials.dart' show NeuraCredentialStorage;
import '../startup/neura_prefs_cache.dart';

class _SecureScheduledBackupStorage implements NeuraCredentialStorage {
  const _SecureScheduledBackupStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

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

  final NeuraCredentialStorage _storage;

  bool get enabled =>
      NeuraPrefsCache.prefsOrNull?.getBool(_keyEnabled) ?? false;

  Future<void> enable(String passphrase) async {
    await _storage.write(key: _keyPassphrase, value: passphrase);
    await NeuraPrefsCache.prefs.setBool(_keyEnabled, true);
  }

  Future<void> disable() async {
    await NeuraPrefsCache.prefs.setBool(_keyEnabled, false);
    await _storage.delete(key: _keyPassphrase);
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
  }) async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_keyLastRunAt, at.toUtc().toIso8601String());
    await prefs.setString(_keyLastOutcome, outcome.name);
    if (error == null) {
      await prefs.remove(_keyLastError);
    } else {
      await prefs.setString(_keyLastError, error);
    }
  }

  Future<void> clearForDataWipe() async {
    await NeuraPrefsCache.prefs.setBool(_keyEnabled, false);
    await NeuraPrefsCache.prefs.remove(_keyLastRunAt);
    await NeuraPrefsCache.prefs.remove(_keyLastOutcome);
    await NeuraPrefsCache.prefs.remove(_keyLastError);
    await _storage.delete(key: _keyPassphrase);
  }
}
