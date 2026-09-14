import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/services/neura_provider_credentials.dart'
    show NeuraCredentialStorage;
import 'package:neuro_companion/services/scheduled_backup_settings.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

class _FakeSecureStorage implements NeuraCredentialStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  late _FakeSecureStorage storage;
  late ScheduledBackupSettings settings;

  setUp(() {
    storage = _FakeSecureStorage();
    settings = ScheduledBackupSettings.forTesting(storage: storage);
  });

  test('starts disabled with no passphrase', () async {
    expect(settings.enabled, isFalse);
    expect(await settings.passphrase(), isNull);
    expect(settings.lastRunAt, isNull);
    expect(settings.lastOutcome, isNull);
  });

  test('enable stores the passphrase only in secure storage', () async {
    await settings.enable('a very good passphrase');

    expect(settings.enabled, isTrue);
    expect(await settings.passphrase(), 'a very good passphrase');
    expect(storage.values.values, contains('a very good passphrase'));
  });

  test('disable clears both the flag and the passphrase', () async {
    await settings.enable('a very good passphrase');
    await settings.disable();

    expect(settings.enabled, isFalse);
    expect(await settings.passphrase(), isNull);
  });

  test('recordOutcome tracks success without an error', () async {
    final at = DateTime.utc(2026, 1, 1, 8);
    await settings.recordOutcome(
      at: at,
      outcome: ScheduledBackupOutcome.success,
    );

    expect(settings.lastRunAt?.toUtc(), at);
    expect(settings.lastOutcome, ScheduledBackupOutcome.success);
    expect(settings.lastError, isNull);
  });

  test('recordOutcome tracks a failure with its error message', () async {
    final at = DateTime.utc(2026, 1, 2, 9);
    await settings.recordOutcome(
      at: at,
      outcome: ScheduledBackupOutcome.failed,
      error: 'disk full',
    );

    expect(settings.lastRunAt?.toUtc(), at);
    expect(settings.lastOutcome, ScheduledBackupOutcome.failed);
    expect(settings.lastError, 'disk full');
  });

  test('a later successful recordOutcome clears a previous error', () async {
    await settings.recordOutcome(
      at: DateTime.utc(2026, 1, 1),
      outcome: ScheduledBackupOutcome.failed,
      error: 'disk full',
    );
    await settings.recordOutcome(
      at: DateTime.utc(2026, 1, 2),
      outcome: ScheduledBackupOutcome.success,
    );

    expect(settings.lastOutcome, ScheduledBackupOutcome.success);
    expect(settings.lastError, isNull);
  });

  test('clearForDataWipe forgets everything, including the passphrase',
      () async {
    await settings.enable('a very good passphrase');
    await settings.recordOutcome(
      at: DateTime.utc(2026, 1, 1),
      outcome: ScheduledBackupOutcome.success,
    );

    await settings.clearForDataWipe();

    expect(settings.enabled, isFalse);
    expect(await settings.passphrase(), isNull);
    expect(settings.lastRunAt, isNull);
    expect(settings.lastOutcome, isNull);
    expect(storage.values, isEmpty);
  });
}
