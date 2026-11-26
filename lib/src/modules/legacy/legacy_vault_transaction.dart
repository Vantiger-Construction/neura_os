import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'legacy_vault_zip_codec.dart';

/// Injectable file boundary for synthetic IO, interruption and recovery tests.
class LegacyVaultFileOperations {
  const LegacyVaultFileOperations();

  Future<void> write(File file, List<int> bytes) async {
    await file.create(exclusive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> renameFile(File file, String destination) async {
    await file.rename(destination);
  }

  Future<void> renameDirectory(Directory directory, String destination) async {
    await directory.rename(destination);
  }

  Future<void> deleteFile(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteDirectory(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<List<int>> read(File file, int limit) =>
      readLegacyBounded(file.openRead(), limit);
}

Future<List<int>> readLegacyBounded(Stream<List<int>> stream, int limit) async {
  final chunks = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (chunk.length > limit - chunks.length) {
      throw const LegacyVaultZipException(
          'File exceeds the configured byte limit.');
    }
    chunks.add(chunk);
  }
  return chunks.takeBytes();
}

/// Validate every existing descendant without following links out of the root.
Future<File> legacyVaultFile(Directory root, String relative,
    {bool createParents = false}) async {
  final normalized = normalizeLegacyRelativePath(relative);
  final parts = normalized.split('/');
  final canonical = await root.resolveSymbolicLinks();
  var parent = root;
  for (final part in parts.take(parts.length - 1)) {
    final next = Directory('${parent.path}/$part');
    var type = await FileSystemEntity.type(next.path, followLinks: false);
    if (type == FileSystemEntityType.notFound && createParents) {
      await next.create();
      type = await FileSystemEntity.type(next.path, followLinks: false);
    }
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw const LegacyVaultZipException(
          'Vault path is blocked or contains a link.');
    }
    if (type == FileSystemEntityType.directory) {
      _checkContained(canonical, await next.resolveSymbolicLinks());
    }
    parent = next;
  }
  final file = File('${parent.path}/${parts.last}');
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw const LegacyVaultZipException(
        'Vault file is blocked or contains a link.');
  }
  if (type == FileSystemEntityType.file) {
    _checkContained(canonical, await file.resolveSymbolicLinks());
  }
  return file;
}

void _checkContained(String root, String candidate) {
  final base = Platform.isWindows ? root.toLowerCase() : root;
  final path = Platform.isWindows ? candidate.toLowerCase() : candidate;
  if (!path.startsWith('$base${Platform.pathSeparator}')) {
    throw const LegacyVaultZipException('Vault path is outside its root.');
  }
}

class LegacyVaultImportResult {
  const LegacyVaultImportResult(
      {this.imported = 0,
      this.skipped = 0,
      this.cancelled = false,
      this.cleanupPending = false});
  final int imported;
  final int skipped;
  final bool cancelled;
  final bool cleanupPending;

  String get description => cancelled
      ? 'Import cancelled.'
      : 'Imported $imported capsule(s); skipped $skipped existing capsule(s).'
          '${cleanupPending ? ' Temporary cleanup will resume on the next vault access.' : ''}';
}

/// New capsules are staged first. Journaled moves are visible through the
/// service only after commit. Interrupted moves roll back before the next read.
/// This is recoverable multi-file commit, not filesystem-wide atomic rename.
class LegacyVaultTransaction {
  LegacyVaultTransaction({this.files = const LegacyVaultFileOperations()});
  final LegacyVaultFileOperations files;
  static final _stageName = RegExp(r'^\.neura-import-[a-f0-9]{32}$');
  static final _unpreparedName = RegExp(r'^\.neura-staging-[a-f0-9]{32}$');
  static const _journalLimit = 4 * 1024 * 1024;

  Future<void> recover(Directory vault) async {
    await for (final entry in vault.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (_unpreparedName.hasMatch(name) && entry is Directory) {
        final owner = await legacyVaultFile(entry, 'owner');
        if (await owner.exists()) {
          final token =
              utf8.decode(await files.read(owner, 64), allowMalformed: true);
          if (name == '.neura-staging-$token') {
            await files.deleteDirectory(entry);
          }
        }
        continue;
      }
      if (!_stageName.hasMatch(name)) continue;
      if (entry is! Directory) {
        throw const LegacyVaultZipException(
            'Import recovery is blocked by an unsafe path.');
      }
      await _recoverStage(vault, entry);
    }
  }

  Future<LegacyVaultImportResult> install(Directory vault,
      LegacyVaultZipPlan plan, void Function() checkpoint) async {
    final existing = <String, FileSystemEntityType>{};
    await for (final entry in vault.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      existing[name.toLowerCase()] =
          await FileSystemEntity.type(entry.path, followLinks: false);
    }
    final ids = <String>[];
    var skipped = 0;
    for (final capsule in plan.capsules) {
      final fileType = existing['capsule_${capsule.id}.json'.toLowerCase()];
      if (fileType == FileSystemEntityType.file) {
        skipped++;
        continue; // The capsule and all its attachments are skipped together.
      }
      if (fileType != null ||
          existing.containsKey('capsule_${capsule.id}'.toLowerCase())) {
        throw const LegacyVaultZipException(
            'A capsule destination is already occupied. Nothing was imported.');
      }
      ids.add(capsule.id);
    }
    if (ids.isEmpty) return LegacyVaultImportResult(skipped: skipped);
    checkpoint();
    final token = List.generate(16, (_) => Random.secure().nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    var stage = Directory('${vault.path}/.neura-staging-$token');
    await stage.create();
    var prepared = false;
    var committed = false;
    try {
      await _write(File('${stage.path}/owner'), utf8.encode(token));
      var payload = Directory('${stage.path}/payload');
      await payload.create();
      final hashes = <String, String>{};
      for (final id in ids) {
        await Directory('${payload.path}/capsule_$id').create();
        await _write(File('${payload.path}/capsule_$id/.import-owner'),
            utf8.encode(token));
      }
      for (final entry in plan.files.entries) {
        final admitted = ids.any((id) =>
            entry.key == 'capsule_$id.json' ||
            entry.key.startsWith('capsule_$id/'));
        if (!admitted) continue;
        checkpoint();
        final target =
            await legacyVaultFile(payload, entry.key, createParents: true);
        await _write(target, entry.value);
        hashes[entry.key] = await legacyZipHash(entry.value);
      }
      await _write(
          File('${stage.path}/journal.json'),
          utf8.encode(jsonEncode({
            'format': 'neura-legacy-import',
            'version': 1,
            'token': token,
            'ids': ids,
            'hashes': hashes,
          })));
      // Only a fully written ownership journal can acquire the recoverable
      // import name. A crash during earlier staging never blocks normal reads.
      final admitted = Directory('${vault.path}/.neura-import-$token');
      await files.renameDirectory(stage, admitted.path);
      stage = admitted;
      payload = Directory('${stage.path}/payload');
      prepared = true;
      checkpoint();
      // Attachments/ownership marker precede JSON visibility for every capsule.
      for (final id in ids) {
        checkpoint();
        if (await FileSystemEntity.type('${vault.path}/capsule_$id',
                    followLinks: false) !=
                FileSystemEntityType.notFound ||
            await FileSystemEntity.type('${vault.path}/capsule_$id.json',
                    followLinks: false) !=
                FileSystemEntityType.notFound) {
          throw const LegacyVaultZipException(
              'Capsule destination changed during import.');
        }
        await files.renameDirectory(Directory('${payload.path}/capsule_$id'),
            '${vault.path}/capsule_$id');
      }
      for (final id in ids) {
        checkpoint();
        final target = await legacyVaultFile(vault, 'capsule_$id.json');
        if (await target.exists()) {
          throw const LegacyVaultZipException(
              'Capsule destination changed during import.');
        }
        await files.renameFile(
            File('${payload.path}/capsule_$id.json'), target.path);
      }
      checkpoint();
      for (final entry in hashes.entries) {
        final file = await legacyVaultFile(vault, entry.key);
        if (await legacyZipHash(await files.read(file, 64 * 1024 * 1024)) !=
            entry.value) {
          throw const LegacyVaultZipException(
              'Imported data changed before commit.');
        }
      }
      checkpoint();
      await _write(File('${stage.path}/committed'), utf8.encode(token));
      committed = true;
      try {
        await _recoverStage(vault, stage);
      } on LegacyVaultZipException {
        rethrow;
      } catch (_) {
        return LegacyVaultImportResult(
            imported: ids.length, skipped: skipped, cleanupPending: true);
      }
      return LegacyVaultImportResult(imported: ids.length, skipped: skipped);
    } catch (_) {
      if (committed) rethrow;
      var recoveredCommit = false;
      try {
        if (prepared) {
          recoveredCommit = await _recoverStage(vault, stage);
        } else {
          await files.deleteDirectory(
              stage); // Only this invocation's staging directory.
        }
      } catch (_) {
        throw const LegacyVaultZipException(
            'Import failed. Recovery must finish before the vault can reopen.');
      }
      if (recoveredCommit) {
        return LegacyVaultImportResult(imported: ids.length, skipped: skipped);
      }
      throw const LegacyVaultZipException(
          'Import failed; no new capsules were kept.');
    }
  }

  Future<bool> _recoverStage(Directory vault, Directory stage) async {
    final owner = await legacyVaultFile(stage, 'owner');
    if (!await owner.exists()) {
      // No ownership proof: preserve unknown data rather than deleting it.
      throw const LegacyVaultZipException(
          'Unrecognized import staging directory needs review.');
    }
    final token = utf8.decode(await files.read(owner, 64));
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(token) ||
        !stage.path.endsWith('.neura-import-$token')) {
      throw const LegacyVaultZipException(
          'Import ownership record is invalid.');
    }
    final journal = await legacyVaultFile(stage, 'journal.json');
    if (!await journal.exists()) {
      throw const LegacyVaultZipException(
          'Import journal is missing; recovery needs review.');
    }
    final value =
        jsonDecode(utf8.decode(await files.read(journal, _journalLimit)))
            as Map;
    if (value['format'] != 'neura-legacy-import' ||
        value['version'] != 1 ||
        value['token'] != token) {
      throw const LegacyVaultZipException('Import recovery record is invalid.');
    }
    final ids = (value['ids'] as List).cast<String>();
    final hashes = (value['hashes'] as Map).cast<String, String>();
    if (ids.isEmpty ||
        ids.length > 512 ||
        hashes.length > 4096 ||
        ids.toSet().length != ids.length) {
      throw const LegacyVaultZipException(
          'Import recovery record exceeds its limits.');
    }
    for (final id in ids) {
      validateLegacyCapsuleId(id);
      if (!hashes.containsKey('capsule_$id.json')) {
        throw const LegacyVaultZipException(
            'Import recovery record is incomplete.');
      }
    }
    for (final entry in hashes.entries) {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value) ||
          !ids.any((id) =>
              entry.key == 'capsule_$id.json' ||
              _attachmentOf(id, entry.key))) {
        throw const LegacyVaultZipException(
            'Import recovery destination is invalid.');
      }
    }
    final commitFile = await legacyVaultFile(stage, 'committed');
    final committed = await commitFile.exists() &&
        utf8.decode(await files.read(commitFile, 64)) == token;
    // Verify ownership and complete inventories before any deletion.
    for (final id in ids) {
      final dir = Directory('${vault.path}/capsule_$id');
      final dirType = await FileSystemEntity.type(dir.path, followLinks: false);
      final json = await legacyVaultFile(vault, 'capsule_$id.json');
      if (dirType == FileSystemEntityType.directory) {
        final marker = await legacyVaultFile(dir, '.import-owner');
        if (await marker.exists()) {
          if (utf8.decode(await files.read(marker, 64)) != token) {
            throw const LegacyVaultZipException(
                'Import destination ownership changed.');
          }
        } else if (!committed) {
          throw const LegacyVaultZipException(
              'Import destination ownership changed.');
        }
        final expected = <String, String>{
          for (final e
              in hashes.entries.where((e) => e.key.startsWith('capsule_$id/')))
            e.key.substring('capsule_$id/'.length): e.value
        };
        final seen = <String>{};
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          final relative =
              entity.path.substring(dir.path.length + 1).replaceAll('\\', '/');
          if (entity is Directory && relative == 'attachments') continue;
          if (relative == '.import-owner' && entity is File) continue;
          if (entity is! File ||
              !expected.containsKey(relative) ||
              await legacyZipHash(await files.read(entity, 64 * 1024 * 1024)) !=
                  expected[relative]) {
            throw const LegacyVaultZipException(
                'Import destination inventory changed.');
          }
          seen.add(relative);
        }
        if (seen.length != expected.length) {
          throw const LegacyVaultZipException(
              'Imported attachment inventory is incomplete.');
        }
      } else if (dirType != FileSystemEntityType.notFound ||
          committed ||
          await json.exists()) {
        throw const LegacyVaultZipException(
            'Import destination ownership changed.');
      }
      if (await json.exists()) {
        if (await legacyZipHash(await files.read(json, 1024 * 1024)) !=
            hashes['capsule_$id.json']) {
          throw const LegacyVaultZipException(
              'Imported capsule changed during recovery.');
        }
      } else if (committed) {
        throw const LegacyVaultZipException('Committed import is incomplete.');
      }
    }
    if (!committed) {
      for (final id in ids) {
        await files
            .deleteFile(await legacyVaultFile(vault, 'capsule_$id.json'));
        await files.deleteDirectory(Directory('${vault.path}/capsule_$id'));
      }
    } else {
      for (final id in ids) {
        await files.deleteFile(await legacyVaultFile(
            Directory('${vault.path}/capsule_$id'), '.import-owner'));
      }
    }
    // A committed journal survives any incomplete marker cleanup; recovery
    // accepts missing markers only for a verified committed inventory.
    await files.deleteDirectory(stage);
    return committed;
  }

  Future<void> _write(File file, List<int> bytes) async {
    await files.write(file, bytes);
    if (await legacyZipHash(await files.read(file, bytes.length)) !=
        await legacyZipHash(bytes)) {
      throw const LegacyVaultZipException(
          'Written import data failed verification.');
    }
  }

  bool _attachmentOf(String id, String relative) {
    try {
      return legacyAttachmentPath(id, relative) == relative;
    } catch (_) {
      return false;
    }
  }
}
