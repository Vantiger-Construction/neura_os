import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/src/modules/legacy/legacy_vault_service.dart';
import 'package:neuro_companion/src/modules/legacy/legacy_vault_transaction.dart';
import 'package:neuro_companion/src/modules/legacy/legacy_vault_zip_codec.dart'
    show LegacyVaultZipCodec;
import 'package:path/path.dart' as p;

import 'legacy_zip_fixture.dart';

class FailingZipFiles extends LegacyVaultFileOperations {
  bool failStageWrite = false;
  bool failCommitWrite = false;
  bool throwAfterCommit = false;
  bool corruptCommit = false;
  bool blockRollback = false;
  bool failCleanupOnce = false;
  int? failJsonRename;
  int jsonRenames = 0;
  final renameReached = Completer<void>();
  final releaseRename = Completer<void>();
  bool pauseRename = false;
  bool corruptStageWrite = false;
  bool failExportWrite = false;
  bool failExportRename = false;
  bool corruptExportWrite = false;

  @override
  Future<void> write(File file, List<int> bytes) async {
    final name = p.basename(file.path);
    if (name == 'committed') {
      if (corruptCommit) {
        await super.write(file, List.filled(bytes.length, 0));
        return;
      }
      if (throwAfterCommit) {
        await super.write(file, bytes);
        throw const FileSystemException('Synthetic error after durable commit');
      }
    }
    if ((corruptStageWrite && p.split(file.path).contains('payload')) ||
        (corruptExportWrite && file.path.endsWith('.partial'))) {
      final changed = <int>[...bytes];
      if (changed.isEmpty) {
        changed.add(1);
      } else {
        changed[0] ^= 1;
      }
      await super.write(file, changed);
      return;
    }
    if (failExportWrite && file.path.endsWith('.partial')) {
      await super.write(file, bytes.take(10).toList());
      throw const FileSystemException('Synthetic export write failure');
    }
    if (failStageWrite &&
        p.split(file.path).contains('payload') &&
        name == 'notes.txt') {
      throw const FileSystemException('Synthetic stage write failure');
    }
    if (failCommitWrite && name == 'committed') {
      await super.write(file, []);
      throw const FileSystemException('Synthetic incomplete commit marker');
    }
    await super.write(file, bytes);
  }

  @override
  Future<void> renameFile(File file, String destination) async {
    if (failExportRename && file.path.endsWith('.partial')) {
      throw const FileSystemException('Synthetic export promotion failure');
    }
    if (p.split(file.path).contains('payload') && file.path.endsWith('.json')) {
      jsonRenames++;
      if (pauseRename && !renameReached.isCompleted) {
        renameReached.complete();
        await releaseRename.future;
      }
      if (jsonRenames == failJsonRename) {
        throw const FileSystemException('Synthetic commit rename failure');
      }
    }
    await super.renameFile(file, destination);
  }

  @override
  Future<void> deleteDirectory(Directory directory) async {
    final name = p.basename(directory.path);
    if (blockRollback && name.startsWith('capsule_')) {
      throw const FileSystemException('Synthetic rollback failure');
    }
    if (failCleanupOnce && name.startsWith('.neura-import-')) {
      failCleanupOnce = false;
      throw const FileSystemException('Synthetic cleanup failure');
    }
    await super.deleteDirectory(directory);
  }
}

void main() {
  test('a prepared recovery directory without its journal is preserved',
      () async {
    final f = await LegacyZipFixture.create();
    await f.run(() async {
      final service = f.service();
      await service.saveCapsule(fictionalCapsule('existing'));
      const token = '0123456789abcdef0123456789abcdef';
      final stage = Directory('${f.vault.path}/.neura-import-$token');
      await stage.create();
      await File('${stage.path}/owner').writeAsString(token);
      final before = await fictionalSnapshot(f.vault);
      await expectLater(
          service.listCapsules(), throwsA(isA<LegacyVaultZipException>()));
      expect(await fictionalSnapshot(f.vault), before);
    });
  });
  for (final conflict in ['name', 'method', 'flags', 'size']) {
    test('rejects conflicting local and directory $conflict before import',
        () async {
      final f = await LegacyZipFixture.create();
      final bytes = Uint8List.fromList(fictionalZip({
        'capsules/capsule_one.json':
            utf8.encode(fictionalCapsule('one').toJson())
      }));
      final view = ByteData.sublistView(bytes);
      switch (conflict) {
        case 'name':
          bytes[30] = 'x'.codeUnitAt(0);
        case 'method':
          view.setUint16(8, 12, Endian.little);
        case 'flags':
          view.setUint16(
              6, view.getUint16(6, Endian.little) ^ 1, Endian.little);
        case 'size':
          view.setUint32(22, 0, Endian.little);
      }
      final zip = await f.zip(bytes);
      await f.run(() async {
        await expectLater(f.service().importVaultZip(zip),
            throwsA(isA<LegacyVaultZipException>()));
        expect(await fictionalSnapshot(f.vault), isEmpty);
      });
    });
  }
  test('an error after a valid durable commit reports the retained import',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    await f.run(() async {
      final operations = FailingZipFiles()..throwAfterCommit = true;
      final result =
          await f.service(files: operations).importVaultZipResult(zip);
      expect(result.imported, 2);
      expect((await f.service().listCapsules()).length, 2);
    });
  });
  test('a corrupted commit marker is verified and rolls back the import',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.7.1', 'vault_raw');
    await f.run(() async {
      final operations = FailingZipFiles()..corruptCommit = true;
      await expectLater(f.service(files: operations).importVaultZip(zip),
          throwsA(isA<LegacyVaultZipException>()));
      expect(await fictionalSnapshot(f.vault), isEmpty);
    });
  });
  test('restart cleans an owned unprepared stage and preserves unknown data',
      () async {
    final f = await LegacyZipFixture.create();
    await f.run(() async {
      final service = f.service();
      await service.saveCapsule(fictionalCapsule('existing'));
      const token = '0123456789abcdef0123456789abcdef';
      final owned = Directory('${f.vault.path}/.neura-staging-$token');
      await owned.create();
      await File('${owned.path}/owner').writeAsString(token);
      await File('${owned.path}/unfinished').writeAsString('Fictional payload');
      final unknown = Directory(
          '${f.vault.path}/.neura-staging-fedcba9876543210fedcba9876543210');
      await unknown.create();
      final unknownFile = File('${unknown.path}/unrecognized');
      await unknownFile.writeAsString('Fictional data without ownership');
      expect((await service.listCapsules()).map((c) => c.id), ['existing']);
      expect(await owned.exists(), isFalse);
      expect(
          await unknownFile.readAsString(), 'Fictional data without ownership');
    });
  });
  test('changed interrupted destinations block recovery and preserve data',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    await f.run(() async {
      final operations = FailingZipFiles()
        ..failJsonRename = 2
        ..blockRollback = true;
      await expectLater(f.service(files: operations).importVaultZip(zip),
          throwsA(isA<LegacyVaultZipException>()));
      expect(operations.jsonRenames, 2);
      final dir = (await f.vault.list().toList())
          .whereType<Directory>()
          .firstWhere((d) => p.basename(d.path).startsWith('capsule_'));
      await File('${dir.path}/unexpected.txt')
          .writeAsString('Fictional new data');
      final before = await fictionalSnapshot(f.vault);
      await expectLater(
          f.service().listCapsules(), throwsA(isA<LegacyVaultZipException>()));
      expect(await fictionalSnapshot(f.vault), before);
    });
  });
  for (final failure in ['write', 'rename', 'verify']) {
    test(
        'failed export $failure preserves previous ZIP and removes its partial file',
        () async {
      final f = await LegacyZipFixture.create();
      await f.run(() async {
        final service = f.service();
        await service.saveCapsule(fictionalCapsule('one'));
        await service.exportVaultZip();
        final before = await fictionalSnapshot(f.temporary);
        final operations = FailingZipFiles()
          ..failExportWrite = failure == 'write'
          ..failExportRename = failure == 'rename'
          ..corruptExportWrite = failure == 'verify';
        await expectLater(
            f.service(files: operations).exportVaultZip(), throwsA(anything));
        expect(await fictionalSnapshot(f.temporary), before);
      });
    });
  }
  test('corrupted stage bytes are detected before promoting any capsule',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.7.1', 'vault_raw');
    await f.run(() async {
      final operations = FailingZipFiles()..corruptStageWrite = true;
      await expectLater(f.service(files: operations).importVaultZip(zip),
          throwsA(isA<LegacyVaultZipException>()));
      expect(await fictionalSnapshot(f.vault), isEmpty);
    });
  });
  test('valid ZIP CRCs cannot hide a mismatched content manifest', () async {
    final f = await LegacyZipFixture.create();
    await f.run(() async {
      final service = f.service();
      await service.saveCapsule(fictionalCapsule('one'));
      final exported = await service.exportVaultZip();
      final decoded =
          const LegacyVaultZipCodec().decode(await exported.readAsBytes());
      final entries = <String, List<int>>{
        for (final file in decoded.files) file.name: file.content
      };
      final capsule =
          fictionalCapsule('one').copyWith(title: 'Fictional changed record');
      entries['capsules/capsule_one.json'] = utf8.encode(capsule.toJson());
      final changed = await f.zip(fictionalZip(entries), name: 'changed.zip');
      final before = await fictionalSnapshot(f.vault);
      await expectLater(service.importVaultZip(changed),
          throwsA(isA<LegacyVaultZipException>()));
      expect(await fictionalSnapshot(f.vault), before);
    });
  });
  test('duplicate raw ZIP names are rejected before decoder deduplication',
      () async {
    final f = await LegacyZipFixture.create();
    final bytes = Uint8List.fromList(fictionalZip({
      'capsules/a.json': utf8.encode(fictionalCapsule('one').toJson()),
      'capsules/b.json': utf8.encode(fictionalCapsule('two').toJson()),
    }));
    final view = ByteData.sublistView(bytes);
    var count = 0;
    for (var at = 0; at + 46 <= bytes.length; at++) {
      if (view.getUint32(at, Endian.little) != 0x02014b50) continue;
      if (++count == 2) {
        bytes[at + 46 + 'capsules/'.length] = 'a'.codeUnitAt(0);
        final local = view.getUint32(at + 42, Endian.little);
        bytes[local + 30 + 'capsules/'.length] = 'a'.codeUnitAt(0);
        break;
      }
    }
    expect(count, 2);
    final zip = await f.zip(bytes);
    await f.run(() async {
      await expectLater(
          f.service().importVaultZip(zip),
          throwsA(isA<LegacyVaultZipException>()
              .having((e) => e.message, 'message', contains('duplicate'))));
      expect(await fictionalSnapshot(f.vault), isEmpty);
    });
  });
  for (final producer in ['4.6.0', '4.7.1']) {
    for (final name in [
      'truncated_eocd',
      'truncated_local_header',
      'empty_input',
      'not_a_zip',
      'crc_only_corruption',
      'invalid_json_after_valid',
      'invalid_utf8_after_valid',
      'invalid_encrypted_fields',
      'packet_only_attachment',
      'missing_attachments',
      'duplicate_id',
      'duplicate_existing_attachment',
      'extra_path_attachment',
      'packet_raw',
      'packet_clear',
      'packet_wrong'
    ]) {
      test(
          'rejects $producer $name before leaving any capsule or attachment writes',
          () async {
        final f = await LegacyZipFixture.create();
        final zip = await f.archive(producer, name);
        final service = f.service();
        await f.run(() async {
          await service.vaultDirectory();
          final before = await fictionalSnapshot(f.vault);
          await expectLater(service.importVaultZip(zip),
              throwsA(isA<LegacyVaultZipException>()));
          expect(await fictionalSnapshot(f.vault), before);
          expect(await service.listCapsules(), isEmpty);
        });
      });
    }
  }
  for (final failure in ['stage', 'rename', 'commit_marker']) {
    test('$failure IO failure rolls back operation-owned destinations',
        () async {
      final f = await LegacyZipFixture.create();
      final zip = await f.archive('4.7.1', 'vault_raw');
      final operations = FailingZipFiles()
        ..failStageWrite = failure == 'stage'
        ..failJsonRename = failure == 'rename' ? 2 : null
        ..failCommitWrite = failure == 'commit_marker';
      final service = f.service(files: operations);
      await f.run(() async {
        await service.saveCapsule(fictionalCapsule('existing'));
        final before = await fictionalSnapshot(f.vault);
        await expectLater(service.importVaultZip(zip),
            throwsA(isA<LegacyVaultZipException>()));
        expect(await fictionalSnapshot(f.vault), before);
      });
    });
  }
  test('restart recovery removes a partially committed import before reads',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    final operations = FailingZipFiles()
      ..failJsonRename = 2
      ..blockRollback = true;
    await f.run(() async {
      final service = f.service(files: operations);
      await service.saveCapsule(fictionalCapsule('existing'));
      final before = await fictionalSnapshot(f.vault);
      await expectLater(
          service.importVaultZip(zip), throwsA(isA<LegacyVaultZipException>()));
      expect(
          (await f.vault.list().toList())
              .any((e) => p.basename(e.path).startsWith('.neura-import-')),
          isTrue);
      final restarted = f.service();
      expect((await restarted.listCapsules()).map((c) => c.id), ['existing']);
      expect(await fictionalSnapshot(f.vault), before);
    });
  });
  test('committed cleanup resumes without rolling back successful capsules',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    await f.run(() async {
      final operations = FailingZipFiles()..failCleanupOnce = true;
      final result =
          await f.service(files: operations).importVaultZipResult(zip);
      expect(result.imported, 2);
      expect(result.cleanupPending, isTrue);
      expect((await f.service().listCapsules()).length, 2);
      expect(
          (await f.vault.list().toList())
              .any((e) => p.basename(e.path).startsWith('.neura-import-')),
          isFalse);
    });
  });
  test('concurrent imports serialize and never attach files to skipped IDs',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    await f.run(() async {
      final results = await Future.wait([
        f.service().importVaultZipResult(zip),
        f.service().importVaultZipResult(zip)
      ]);
      expect(results.map((r) => r.imported), [2, 0]);
      expect(results.last.skipped, 2);
      expect((await f.service().listCapsules()).length, 2);
    });
  });
  test('full-wipe admission revokes an import and drains its rollback',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    await f.run(() async {
      final operations = FailingZipFiles()..pauseRename = true;
      final service = f.service(files: operations);
      final importing = service.importVaultZip(zip);
      final rejected =
          expectLater(importing, throwsA(isA<LegacyVaultZipException>()));
      await operations.renameReached.future;
      LegacyVaultService.suspendForDataWipe();
      var drained = false;
      final drain =
          LegacyVaultService.drainForDataWipe().then((_) => drained = true);
      expect(drained, isFalse);
      operations.releaseRename.complete();
      await rejected;
      await drain;
      expect(await fictionalSnapshot(f.vault), isEmpty);
      await expectLater(
          service.listCapsules(), throwsA(isA<LegacyVaultZipException>()));
    });
  });
  test('scoped wipe waits for rollback and allows fresh operations afterward',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    await f.run(() async {
      final operations = FailingZipFiles()..pauseRename = true;
      final service = f.service(files: operations);
      final rejected = expectLater(
          service.importVaultZip(zip), throwsA(isA<LegacyVaultZipException>()));
      await operations.renameReached.future;
      final wipe = LegacyVaultService.withDataWipe(() async {
        expect(await fictionalSnapshot(f.vault), isEmpty);
        await f.vault.delete(recursive: true);
      });
      operations.releaseRename.complete();
      await rejected;
      await wipe;
      expect(await f.vault.exists(), isFalse);
      expect(await service.listCapsules(), isEmpty);
    });
  });
  test(
      'picker cancellation creates no vault or output and late selection is revoked',
      () async {
    final f = await LegacyZipFixture.create();
    await f.run(() async {
      final cancelled = await f
          .service(pickZipFile: () async => null)
          .importVaultZipInteractiveResult();
      expect(cancelled.cancelled, isTrue);
      expect(await f.vault.exists(), isFalse);
      final pick = Completer<SyntheticPickedFile?>();
      final selecting = f
          .service(pickZipFile: () => pick.future)
          .importVaultZipInteractiveResult();
      final rejected =
          expectLater(selecting, throwsA(isA<LegacyVaultZipException>()));
      await LegacyVaultService.withDataWipe(() async {});
      pick.complete(SyntheticPickedFile(() => Stream.value(Uint8List(1))));
      await rejected;
      expect(await f.vault.exists(), isFalse);
    });
  });
  test('unknown-length input stops at its budget without unbounded readAsBytes',
      () async {
    final f = await LegacyZipFixture.create();
    var chunks = 0;
    Stream<Uint8List> input() async* {
      chunks++;
      yield Uint8List(4);
      chunks++;
      yield Uint8List(5);
      chunks++;
      yield Uint8List(1);
    }

    await f.run(() async {
      final service = f.service(
          limits: const LegacyVaultZipLimits(archiveBytes: 8),
          pickZipFile: () async => SyntheticPickedFile(input));
      await expectLater(service.importVaultZipInteractiveResult(),
          throwsA(isA<LegacyVaultZipException>()));
      expect(chunks, 2);
      expect(await fictionalSnapshot(f.vault), isEmpty);
    });
  });
  for (final limits in [
    const LegacyVaultZipLimits(entryBytes: 100),
    const LegacyVaultZipLimits(totalBytes: 200),
    const LegacyVaultZipLimits(entries: 1),
    const LegacyVaultZipLimits(capsules: 1)
  ]) {
    test('declared size/count budgets refuse before import writes $limits',
        () async {
      final f = await LegacyZipFixture.create();
      final zip = await f.archive('4.7.1', 'vault_raw');
      await f.run(() async {
        await expectLater(f.service(limits: limits).importVaultZip(zip),
            throwsA(isA<LegacyVaultZipException>()));
        expect(await fictionalSnapshot(f.vault), isEmpty);
      });
    });
  }
  for (final id in [
    '../outside',
    'x/../../outside',
    'x\\..\\outside',
    'CON:stream',
    ''
  ]) {
    test('unsafe capsule ID is rejected without escaping fixture: $id',
        () async {
      final f = await LegacyZipFixture.create();
      final zip = await f.zip(fictionalZip(
          {'capsules/a.json': utf8.encode(fictionalCapsule(id).toJson())}));
      await f.run(() async {
        await expectLater(f.service().importVaultZip(zip),
            throwsA(isA<LegacyVaultZipException>()));
        expect(await fictionalSnapshot(f.vault), isEmpty);
      });
    });
  }
  for (final name in [
    '..\\escape.txt',
    'CON.txt',
    'a.txt:stream',
    'bad.',
    'bad '
  ]) {
    test('unsafe Windows attachment name is rejected: $name', () async {
      final f = await LegacyZipFixture.create();
      final id = 'fictional';
      final rel = 'capsule_$id/attachments/$name';
      final zip = await f.zip(fictionalZip({
        'capsules/a.json':
            utf8.encode(fictionalCapsule(id, attachments: [rel]).toJson()),
        'attachments/$id/$name': [1, 2, 3]
      }));
      await f.run(() async {
        await expectLater(f.service().importVaultZip(zip),
            throwsA(isA<LegacyVaultZipException>()));
        expect(await fictionalSnapshot(f.vault), isEmpty);
      });
    });
  }
  test(
      'case-folded ZIP names and duplicate capsule IDs cannot collapse silently',
      () async {
    final f = await LegacyZipFixture.create();
    final names = await f.zip(
        fictionalZip({
          'capsules/a.json': utf8.encode(fictionalCapsule('one').toJson()),
          'capsules/A.json': utf8.encode(fictionalCapsule('two').toJson())
        }),
        name: 'names.zip');
    final ids = await f.zip(
        fictionalZip({
          'capsules/a.json': utf8.encode(fictionalCapsule('one').toJson()),
          'capsules/b.json': utf8.encode(fictionalCapsule('one').toJson())
        }),
        name: 'ids.zip');
    await f.run(() async {
      for (final zip in [names, ids]) {
        await expectLater(f.service().importVaultZip(zip),
            throwsA(isA<LegacyVaultZipException>()));
      }
      expect(await fictionalSnapshot(f.vault), isEmpty);
    });
  });
  test('exports refuse missing attachments and leave no partial output',
      () async {
    final f = await LegacyZipFixture.create();
    await f.run(() async {
      final service = f.service();
      await service.saveCapsule(fictionalCapsule('one',
          attachments: ['capsule_one/attachments/missing.txt']));
      await expectLater(service.exportVaultZip(), throwsA(anything));
      await expectLater(service.exportCapsuleZip('one'), throwsA(anything));
      expect(await f.temporary.list().toList(), isEmpty);
    });
  });
  test('a symlinked attachment is never read or exported', () async {
    final f = await LegacyZipFixture.create();
    await f.run(() async {
      final service = f.service();
      final dir = await service.capsuleAttachmentDir('one');
      final outside = File('${f.root.path}/outside.txt');
      await outside.writeAsString('Fictional file outside vault');
      await Link('${dir.path}/link.txt').create(outside.path);
      await service.saveCapsule(fictionalCapsule('one',
          attachments: ['capsule_one/attachments/link.txt']));
      await expectLater(
          service.exportVaultZip(), throwsA(isA<LegacyVaultZipException>()));
      expect(await outside.readAsString(), 'Fictional file outside vault');
    });
  },
      skip: Platform.isWindows
          ? 'Windows symlink permissions require native acceptance.'
          : false);
}
