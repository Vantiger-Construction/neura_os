import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/vault/memory_vault_models.dart';
import 'package:neuro_companion/services/neura_provider_credentials.dart';
import 'package:neuro_companion/services/portable_backup_codec.dart';
import 'package:neuro_companion/services/portable_vault_backup_service.dart';
import 'package:neuro_companion/services/scheduled_backup_settings.dart';
import 'package:neuro_companion/services/vault_item_source.dart';

import '../helpers/data_wipe_fixture.dart';

class _Credentials implements NeuraCredentialStorage {
  final values = <String, String>{};
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

class _Source implements VaultItemSource {
  List<VaultItem> items = [];
  @override
  Future<List<VaultItem>> getItems({required String pin}) async => items;
  @override
  Future<int> importItems({
    required String pin,
    required List<VaultItem> imported,
    required bool Function() mayWrite,
  }) =>
      throw UnsupportedError('No imports in backup fixtures.');
}

class _InterruptedFiles extends ScheduledBackupFileOperations {
  _InterruptedFiles(this.stage);
  final String stage;
  Future<void> Function()? beforePromotion;

  @override
  Future<void> write(File file, String contents) async {
    if (stage == 'partial write') {
      await super.write(file, 'incomplete synthetic envelope');
      throw const FileSystemException('Synthetic write interruption');
    }
    await super.write(file, contents);
  }

  @override
  Future<String> read(File file) async {
    if (stage == 'readback' && file.path.endsWith('.tmp')) {
      return 'synthetic readback failure';
    }
    return super.read(file);
  }

  @override
  Future<void> rename(File file, String destination) async {
    final promoting = file.path.endsWith('.tmp');
    if (promoting) await beforePromotion?.call();
    if ((stage == 'rotate' && destination.endsWith('.previous')) ||
        (stage == 'promote' && promoting)) {
      throw const FileSystemException('Synthetic rename interruption');
    }
    if (stage == 'ignored rename' && promoting) return;
    await super.rename(file, destination);
    if (stage == 'after promote' && promoting) {
      throw const FileSystemException('Synthetic post-rename interruption');
    }
    if (stage == 'corrupt promotion' && promoting) {
      await File(destination).writeAsString('synthetic damaged promotion');
    }
  }

  @override
  Future<void> delete(File file) async {
    if (file.path.endsWith('.previous')) {
      if (stage == 'cleanup') {
        throw const FileSystemException('Synthetic cleanup interruption');
      }
      if (stage == 'ignored cleanup') return;
    }
    await super.delete(file);
  }
}

VaultItem _item(String id) => VaultItem(
      id: id,
      createdAt: DateTime.utc(2026),
      title: 'Synthetic $id',
      body: 'Synthetic body',
      tags: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const passphrase = 'synthetic backup passphrase';
  late DataWipeFixture fixture;
  late _Source source;
  late ScheduledBackupSettings settings;
  late Directory directory;

  PortableVaultBackupService service([ScheduledBackupFileOperations? files]) =>
      PortableVaultBackupService(
        codec: PortableBackupCodec(iterations: 120000),
        store: source,
        scheduledSettings: settings,
        backupDirectory: () async => directory,
        fileOperations: files,
      );

  Future<ScheduledBackupRunResult> run(
    PortableVaultBackupService backup, [
    int day = 1,
  ]) =>
      backup.runScheduledBackupIfDue(
        pin: '1234',
        now: DateTime.utc(2026, 1, day),
      );

  setUp(() async {
    fixture = await DataWipeFixture.create();
    directory = await Directory('${fixture.support.path}/neura/backups')
        .create(recursive: true);
    source = _Source()..items = [_item('old')];
    settings = ScheduledBackupSettings.forTesting(storage: _Credentials());
    await settings.enable(passphrase);
  });

  for (final stage in [
    'partial write',
    'readback',
    'rotate',
    'promote',
    'ignored rename',
    'after promote',
    'corrupt promotion',
    'cleanup',
    'ignored cleanup',
  ]) {
    test('interrupted $stage preserves the previous verified backup', () async {
      final initial = service();
      expect((await run(initial)).status, ScheduledBackupStatus.succeeded);
      final current = await initial.scheduledBackupFile();
      final old = await current.readAsString();
      source.items = [_item('new')];
      expect(
        (await run(service(_InterruptedFiles(stage)), 3)).status,
        ScheduledBackupStatus.failed,
      );
      final previous = File('${current.path}.previous');
      expect(
        (await current.exists() && await current.readAsString() == old) ||
            (await previous.exists() && await previous.readAsString() == old),
        isTrue,
      );
      final reopened = service();
      final result = await run(reopened, 5);
      if (stage == 'partial write' || stage == 'corrupt promotion') {
        expect(
          result.status,
          ScheduledBackupStatus.failed,
          reason: 'Unreadable remnants require explicit recovery.',
        );
        expect(
          (await current.exists() && await current.readAsString() == old) ||
              (await previous.exists() && await previous.readAsString() == old),
          isTrue,
        );
      } else {
        expect(result.status, ScheduledBackupStatus.succeeded);
        final preview = await reopened.previewRestore(
          await current.readAsString(),
          passphrase: passphrase,
        );
        expect(preview.items.single.id, 'new');
        preview.revoke();
        expect(await previous.exists(), isFalse);
        expect(await File('${current.path}.tmp').exists(), isFalse);
      }
    });
  }

  test(
    'restart restores a previous-only backup before the next write',
    () async {
      final initial = service();
      expect((await run(initial)).status, ScheduledBackupStatus.succeeded);
      final current = await initial.scheduledBackupFile();
      final old = await current.readAsString();
      await current.rename('${current.path}.previous');
      final interrupted = service(_InterruptedFiles('partial write'));
      expect((await run(interrupted, 3)).status, ScheduledBackupStatus.failed);
      expect(await current.readAsString(), old);
    },
  );

  test(
    'a completed first temporary backup recovers without a prior file',
    () async {
      final initial = service();
      expect((await run(initial)).status, ScheduledBackupStatus.succeeded);
      final current = await initial.scheduledBackupFile();
      await current.rename('${current.path}.tmp');
      expect((await run(service(), 3)).status, ScheduledBackupStatus.succeeded);
      expect(await current.exists(), isTrue);
      expect(await File('${current.path}.tmp').exists(), isFalse);
    },
  );

  test(
    'wipe tracks an admitted promotion and prevents later cleanup writes',
    () async {
      final initial = service();
      expect((await run(initial)).status, ScheduledBackupStatus.succeeded);
      final entered = Completer<void>();
      final release = Completer<void>();
      final files = _InterruptedFiles('none')
        ..beforePromotion = () async {
          entered.complete();
          await release.future;
        };
      final running = run(service(files), 3);
      await entered.future;
      PortableVaultBackupService.suspendForDataWipe();
      var drained = false;
      final draining = PortableVaultBackupService.drainForDataWipe().then(
        (_) => drained = true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(drained, isFalse);
      release.complete();
      expect((await running).status, ScheduledBackupStatus.failed);
      await draining;
      // Full wipe removes this exact app-owned directory after the drain.
      await directory.delete(recursive: true);
      expect((await run(service(), 5)).status, ScheduledBackupStatus.skipped);
      expect(await directory.exists(), isFalse);
    },
  );
}
