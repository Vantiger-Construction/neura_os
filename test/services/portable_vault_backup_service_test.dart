import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
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
import '../helpers/data_wipe_fixture.dart';

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
  int imports = 0;
  Future<void> Function()? beforeRead;

  @override
  Future<List<VaultItem>> getItems({required String pin}) async {
    await beforeRead?.call();
    lastPin = pin;
    return items;
  }

  @override
  Future<int> importItems({
    required String pin,
    required List<VaultItem> imported,
    required bool Function() mayWrite,
  }) async {
    imports++;
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  late Directory tempDir;
  late _FakeVaultItemSource store;
  late ScheduledBackupSettings settings;
  late PortableVaultBackupService service;
  late FilePickerPlatform originalPicker;
  late _BackupPicker picker;

  setUp(() async {
    PortableVaultBackupService.resetWipeGateForTesting();
    originalPicker = FilePickerPlatform.instance;
    picker = _BackupPicker();
    FilePickerPlatform.instance = picker;
    tempDir = Directory.systemTemp.createTempSync('neura_backup_test_');
    store = _FakeVaultItemSource()..items = [_item('a'), _item('b')];
    settings = ScheduledBackupSettings.forTesting(
      storage: _FakeSecureStorage(),
    );
    // SharedPreferences' mock store persists across tests in this file;
    // start every test from a clean enabled/last-run state.
    await settings.clearForDataWipe();
    ScheduledBackupSettings.resetWipeGateForTesting();
    service = PortableVaultBackupService(
      codec: PortableBackupCodec(),
      store: store,
      scheduledSettings: settings,
      backupDirectory: () async => tempDir,
    );
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPicker;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('a rejected last-run write cannot report a successful scheduled backup',
      () async {
    final fixture = await DataWipeFixture.create();
    await settings.enable('a very good passphrase');
    fixture.preferences.refusedWrites
        .add('flutter.neura.scheduled_backup.last_run_at');
    final result = await service.runScheduledBackupIfDue(pin: '1234');
    expect(result.status, ScheduledBackupStatus.failed);
    expect(settings.lastRunAt, isNull);
    final envelope = await (await service.scheduledBackupFile()).readAsString();
    expect(
        (await service.verifyBackupIntegrity(envelope,
                passphrase: 'a very good passphrase'))
            .isValid,
        isTrue,
        reason:
            'The valid file remains available even when status storage fails.');
  });

  test('overlapping scheduled requests serialize the due check and replacement',
      () async {
    await settings.enable('a very good passphrase');
    final entered = Completer<void>();
    final release = Completer<void>();
    var reads = 0;
    store.beforeRead = () async {
      reads++;
      if (reads == 1) entered.complete();
      await release.future;
    };
    final now = DateTime.utc(2026, 2, 1);
    final first = service.runScheduledBackupIfDue(pin: '1234', now: now);
    await entered.future;
    final secondService = PortableVaultBackupService(
        store: store,
        scheduledSettings: settings,
        backupDirectory: () async => tempDir);
    final second = secondService.runScheduledBackupIfDue(pin: '1234', now: now);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    release.complete();
    expect((await first).status, ScheduledBackupStatus.succeeded);
    expect((await second).status, ScheduledBackupStatus.skipped);
    final envelope = await (await service.scheduledBackupFile()).readAsString();
    expect(
        (await service.verifyBackupIntegrity(envelope,
                passphrase: 'a very good passphrase'))
            .itemCount,
        2);
    expect(reads, 1);
  });

  test('wipe revokes an export before native file saving is admitted',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    store.beforeRead = () async {
      entered.complete();
      await release.future;
    };
    final export =
        service.exportToFile(pin: '1234', passphrase: 'a very good passphrase');
    final rejected = expectLater(export, throwsStateError);
    await entered.future;
    PortableVaultBackupService.suspendForDataWipe();
    var drained = false;
    final draining = PortableVaultBackupService.drainForDataWipe()
        .then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    release.complete();
    await rejected;
    await draining;
    expect(picker.savedBytes, isNull);
  });

  test('timed-out native export remains tracked until the picker finishes',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    picker.beforeSave = () async {
      entered.complete();
      await release.future;
    };
    final export =
        service.exportToFile(pin: '1234', passphrase: 'a very good passphrase');
    final rejected = expectLater(export, throwsStateError);
    await entered.future;
    PortableVaultBackupService.suspendForDataWipe();
    PortableVaultBackupService.wipeDrainTimeout =
        const Duration(milliseconds: 20);
    await expectLater(PortableVaultBackupService.drainForDataWipe(),
        throwsA(isA<TimeoutException>()));
    expect(
        PortableVaultBackupService.resetWipeGateForTesting, throwsStateError);
    release.complete();
    await rejected;
    await PortableVaultBackupService.drainForDataWipe();
    await expectLater(
        service.exportToFile(pin: '1234', passphrase: 'a very good passphrase'),
        throwsStateError);
  });

  test('wipe closes backup admission and drains a delayed directory creation',
      () async {
    await settings.enable('a very good passphrase');
    final entered = Completer<void>();
    final release = Completer<void>();
    service = PortableVaultBackupService(
        store: store,
        scheduledSettings: settings,
        backupDirectory: () async {
          entered.complete();
          await release.future;
          return tempDir;
        });
    final backingUp = service.runScheduledBackupIfDue(pin: '1234');
    await entered.future;
    PortableVaultBackupService.suspendForDataWipe();
    var drained = false;
    final draining = PortableVaultBackupService.drainForDataWipe()
        .then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    final rejected = await service.runScheduledBackupIfDue(pin: '1234');
    expect(rejected.status, ScheduledBackupStatus.skipped);
    release.complete();
    expect((await backingUp).status, ScheduledBackupStatus.failed);
    await draining;
    expect(tempDir.listSync(), isEmpty);
    expect(settings.lastRunAt, isNull,
        reason:
            'A cancelled backup cannot recreate outcome preferences after wipe.');
  });

  group('file picker migration', () {
    test('exported content URI is read and verified without importing',
        () async {
      const passphrase = 'a very good passphrase';
      final destination =
          await service.exportToFile(pin: '1234', passphrase: passphrase);
      expect(destination, 'content://backups/export.neurabackup');
      final saved = picker.savedBytes!;
      expect(utf8.decode(saved), isNot(contains('Body a')));
      final ciphertext = await service.readBackupFile(_BackupFile([saved]));
      final preview =
          await service.previewRestore(ciphertext, passphrase: passphrase);
      expect(preview.items.map((item) => item.id), ['a', 'b']);
      expect(store.imports, 0);
      preview.revoke();
    });

    test('unknown-size streams cannot exceed the backup byte limit', () async {
      await expectLater(
          service.readBackupFile(_BackupFile([
            Uint8List(25 * 1024 * 1024),
            Uint8List(1),
          ])),
          throwsFormatException);
      expect(store.imports, 0);
    });
  });

  group('reviewed restore', () {
    Future<String> envelope() => PortableBackupCodec()
            .encrypt(passphrase: 'a very good passphrase', payload: {
          'type': 'neura-memory-vault',
          'version': 1,
          'items': [_item('a').toJson(), _item('b').toJson()]
        });

    test(
        'verification writes nothing and restores only explicitly selected entries',
        () async {
      final preview = await service.previewRestore(await envelope(),
          passphrase: 'a very good passphrase');
      expect(store.imports, 0);
      expect(preview.items.map((item) => item.id), ['a', 'b']);
      expect(() => preview.items.clear(), throwsUnsupportedError);
      expect(() => preview.items.first.tags.clear(), throwsUnsupportedError);
      expect(
          await service.restorePreview(
              pin: '1234',
              preview: preview,
              mayRestore: () => true,
              selected: {1}),
          1);
      expect(store.items.single.id, 'b');
      expect(store.imports, 1);
      expect(preview.isCurrent, false);
      expect(preview.items, isEmpty);
      await expectLater(
          service.restorePreview(
              pin: '1234',
              preview: preview,
              mayRestore: () => true,
              selected: {0}),
          throwsStateError);
      expect(store.imports, 1);
    });

    test('revoked and foreign reviews cannot write to the vault', () async {
      final preview = await service.previewRestore(await envelope(),
          passphrase: 'a very good passphrase');
      final foreign = PortableVaultBackupService(store: store);
      await expectLater(
          foreign.restorePreview(
              pin: '1234',
              preview: preview,
              mayRestore: () => true,
              selected: {0}),
          throwsStateError);
      preview.revoke();
      await expectLater(
          service.restorePreview(
              pin: '1234',
              preview: preview,
              mayRestore: () => true,
              selected: {0}),
          throwsStateError);
      expect(store.imports, 0);
    });

    test('empty and invalid selections write nothing and leave review usable',
        () async {
      final preview = await service.previewRestore(await envelope(),
          passphrase: 'a very good passphrase');
      for (final selection in [
        <int>{},
        {-1},
        {2}
      ]) {
        await expectLater(
            service.restorePreview(
                pin: '1234',
                preview: preview,
                mayRestore: () => true,
                selected: selection),
            throwsArgumentError);
      }
      expect(store.imports, 0);
      expect(preview.isCurrent, true);
      preview.revoke();
    });

    test('malformed records fail verification before any restore', () async {
      final bad = _item('a').toJson()..['id'] = '';
      final encoded = await PortableBackupCodec()
          .encrypt(passphrase: 'a very good passphrase', payload: {
        'type': 'neura-memory-vault',
        'version': 1,
        'items': [bad]
      });
      await expectLater(
          service.previewRestore(encoded, passphrase: 'a very good passphrase'),
          throwsFormatException);
      final result = await service.verifyBackupIntegrity(encoded,
          passphrase: 'a very good passphrase');
      expect(result.isValid, false);
      expect(store.imports, 0);
    });

    test('a revoked file read is rejected before the stream is opened',
        () async {
      await expectLater(
          service.readBackupFile(_BackupFile([Uint8List(2)]),
              mayRead: () => false),
          throwsStateError);
      expect(store.imports, 0);
    });
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

class _BackupPicker extends FilePickerPlatform {
  Uint8List? savedBytes;
  Future<void> Function()? beforeSave;
  PlatformFile? selected;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    await beforeSave?.call();
    savedBytes = bytes;
    return Uri.parse('content://backups/export.neurabackup');
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async =>
      selected;
}

final class _BackupFile extends PlatformFile {
  _BackupFile(this.chunks);
  final List<Uint8List> chunks;

  @override
  String get name => 'export.neurabackup';

  @override
  Uri get uri => Uri.parse('content://backups/export.neurabackup');

  @override
  int? lengthSync() => null;

  @override
  Future<int?> length() async => null;

  @override
  XFile get xFile => throw UnsupportedError('Use the bounded stream');

  @override
  Future<Uint8List> readAsBytes() =>
      throw UnsupportedError('Use the bounded stream');

  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromIterable(chunks);
}
