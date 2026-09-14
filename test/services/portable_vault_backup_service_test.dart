import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/modules/vault/memory_vault_models.dart';
import 'package:neuro_companion/services/neura_provider_credentials.dart'
    show NeuraCredentialStorage;
import 'package:neuro_companion/services/portable_backup_codec.dart';
import 'package:neuro_companion/services/portable_vault_backup_service.dart';
import 'package:neuro_companion/services/scheduled_backup_settings.dart';
import 'package:neuro_companion/services/vault_item_source.dart';
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

class _FakeVaultItemSource implements VaultItemSource {
  List<VaultItem> items = const [];
  String? lastPin;

  @override
  Future<List<VaultItem>> getItems({required String pin}) async {
    lastPin = pin;
    return items;
  }

  @override
  Future<int> importItems({
    required String pin,
    required List<VaultItem> imported,
  }) async {
    items = imported;
    return imported.length;
  }
}

VaultItem _item(String id) => VaultItem(
      id: id,
      createdAt: DateTime.utc(2026, 1, 1),
      title: 'Title $id',
      body: 'Body $id',
      tags: const ['tag'],
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  late Directory tempDir;
  late _FakeVaultItemSource store;
  late ScheduledBackupSettings settings;
  late PortableVaultBackupService service;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('neura_backup_test_');
    store = _FakeVaultItemSource()..items = [_item('a'), _item('b')];
    settings = ScheduledBackupSettings.forTesting(
      storage: _FakeSecureStorage(),
    );
    // SharedPreferences' mock store persists across tests in this file;
    // start every test from a clean enabled/last-run state.
    await settings.clearForDataWipe();
    service = PortableVaultBackupService(
      codec: PortableBackupCodec(),
      store: store,
      scheduledSettings: settings,
      backupDirectory: () async => tempDir,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('verifyBackupIntegrity', () {
    test('accepts a valid envelope and reports the item count', () async {
      final envelope = await PortableBackupCodec().encrypt(
        passphrase: 'a very good passphrase',
        payload: {
          'type': 'neura-memory-vault',
          'version': 1,
          'items': [_item('a').toJson(), _item('b').toJson()],
        },
      );

      final result = await service.verifyBackupIntegrity(
        envelope,
        passphrase: 'a very good passphrase',
      );

      expect(result.isValid, isTrue);
      expect(result.itemCount, 2);
      expect(result.error, isNull);
    });

    test('rejects the wrong passphrase', () async {
      final envelope = await PortableBackupCodec().encrypt(
        passphrase: 'a very good passphrase',
        payload: {
          'type': 'neura-memory-vault',
          'version': 1,
          'items': <Map<String, dynamic>>[],
        },
      );

      final result = await service.verifyBackupIntegrity(
        envelope,
        passphrase: 'a different passphrase',
      );

      expect(result.isValid, isFalse);
      expect(result.error, isNotNull);
    });

    test('rejects a tampered envelope', () async {
      final envelope = await PortableBackupCodec().encrypt(
        passphrase: 'a very good passphrase',
        payload: {
          'type': 'neura-memory-vault',
          'version': 1,
          'items': <Map<String, dynamic>>[],
        },
      );
      final tampered = envelope.replaceFirst('"data":"', '"data":"AAAA');

      final result = await service.verifyBackupIntegrity(
        tampered,
        passphrase: 'a very good passphrase',
      );

      expect(result.isValid, isFalse);
    });

    test('rejects an envelope of the wrong type', () async {
      final envelope = await PortableBackupCodec().encrypt(
        passphrase: 'a very good passphrase',
        payload: {'type': 'something-else', 'version': 1, 'items': []},
      );

      final result = await service.verifyBackupIntegrity(
        envelope,
        passphrase: 'a very good passphrase',
      );

      expect(result.isValid, isFalse);
      expect(result.error, contains('not a supported'));
    });
  });

  group('runScheduledBackupIfDue', () {
    test('is skipped when the feature is disabled', () async {
      final result = await service.runScheduledBackupIfDue(pin: '1234');

      expect(result.status, ScheduledBackupStatus.skipped);
      expect(result.reason, 'disabled');
      expect(store.lastPin, isNull);
    });

    test('is skipped when enabled but no passphrase is configured', () async {
      // The enabled flag is global SharedPreferences state; set it directly
      // without going through enable(), which always writes a passphrase
      // together with the flag.
      await NeuraPrefsCache.prefs.setBool(
        'neura.scheduled_backup.enabled',
        true,
      );

      final result = await service.runScheduledBackupIfDue(pin: '1234');

      expect(result.status, ScheduledBackupStatus.skipped);
      expect(result.reason, 'no passphrase configured');
    });

    test('writes a self-verified file and records success when due', () async {
      await settings.enable('a very good passphrase');

      final result = await service.runScheduledBackupIfDue(
        pin: '1234',
        now: DateTime.utc(2026, 1, 1, 12),
      );

      expect(result.status, ScheduledBackupStatus.succeeded);
      expect(result.itemCount, 2);
      expect(store.lastPin, '1234');

      final file = await service.scheduledBackupFile();
      expect(await file.exists(), isTrue);
      expect(File('${file.path}.tmp').existsSync(), isFalse);

      expect(settings.lastOutcome, ScheduledBackupOutcome.success);
      expect(settings.lastRunAt?.toUtc(), DateTime.utc(2026, 1, 1, 12));

      final saved = await service.verifyBackupIntegrity(
        await file.readAsString(),
        passphrase: 'a very good passphrase',
      );
      expect(saved.isValid, isTrue);
      expect(saved.itemCount, 2);
    });

    test('is skipped when the interval has not elapsed since the last run',
        () async {
      await settings.enable('a very good passphrase');
      await service.runScheduledBackupIfDue(
        pin: '1234',
        now: DateTime.utc(2026, 1, 1, 12),
      );

      final result = await service.runScheduledBackupIfDue(
        pin: '1234',
        now: DateTime.utc(2026, 1, 1, 13), // 1 hour later.
        interval: const Duration(hours: 24),
      );

      expect(result.status, ScheduledBackupStatus.skipped);
      expect(result.reason, 'not due yet');
    });

    test('runs again once the interval has elapsed', () async {
      await settings.enable('a very good passphrase');
      await service.runScheduledBackupIfDue(
        pin: '1234',
        now: DateTime.utc(2026, 1, 1, 12),
      );

      final result = await service.runScheduledBackupIfDue(
        pin: '1234',
        now: DateTime.utc(2026, 1, 2, 13), // > 24h later.
        interval: const Duration(hours: 24),
      );

      expect(result.status, ScheduledBackupStatus.succeeded);
    });

    test('a later successful run replaces the previous backup file cleanly',
        () async {
      await settings.enable('a very good passphrase');
      await service.runScheduledBackupIfDue(
        pin: '1234',
        now: DateTime.utc(2026, 1, 1, 12),
      );

      store.items = [_item('a'), _item('b'), _item('c')];
      await service.runScheduledBackupIfDue(
        pin: '1234',
        now: DateTime.utc(2026, 1, 2, 13),
      );

      final file = await service.scheduledBackupFile();
      final verified = await service.verifyBackupIntegrity(
        await file.readAsString(),
        passphrase: 'a very good passphrase',
      );
      expect(verified.itemCount, 3);
    });
  });
}
