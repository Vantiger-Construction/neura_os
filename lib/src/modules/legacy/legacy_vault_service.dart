import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'legacy_pdf_cover_builder.dart';
import 'legacy_vault_transaction.dart';
import 'legacy_vault_zip_codec.dart';
import 'models/legacy_capsule.dart';

export 'legacy_vault_transaction.dart' show LegacyVaultImportResult;
export 'legacy_vault_zip_codec.dart'
    show LegacyVaultZipException, LegacyVaultZipLimits;

class LegacyVaultExportResult {
  const LegacyVaultExportResult(this.file, this.encryptedCapsules,
      {this.requestedDecryption = false});
  final File file;
  final int encryptedCapsules;
  final bool requestedDecryption;

  String get description => requestedDecryption && encryptedCapsules > 0
      ? 'Export includes $encryptedCapsules capsule(s) that remain encrypted.'
      : requestedDecryption
          ? 'Decrypted export created. Treat it as sensitive.'
          : 'Export created. Encrypted capsule bodies remain encrypted.';
}

/// Local-only Legacy Vault. Alternate paths/file operations are explicit test
/// seams. Operations serialize with recovery before exposing capsule records.
class LegacyVaultService {
  LegacyVaultService({
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
    Future<PlatformFile?> Function()? pickZipFile,
    LegacyVaultFileOperations files = const LegacyVaultFileOperations(),
    LegacyVaultZipLimits limits = const LegacyVaultZipLimits(),
  })  : _documents = documentsDirectory ?? getApplicationDocumentsDirectory,
        _temporary = temporaryDirectory ?? getTemporaryDirectory,
        _pickZipFile = pickZipFile ??
            (() => FilePicker.pickFile(
                type: FileType.custom, allowedExtensions: const ['zip'])),
        _files = files,
        _codec = LegacyVaultZipCodec(limits: limits),
        _transactions = LegacyVaultTransaction(files: files) {
    limits.validate();
  }

  static final instance = LegacyVaultService();
  static const _vaultFolder = 'neura_legacy_vault';
  final Future<Directory> Function() _documents;
  final Future<Directory> Function() _temporary;
  final Future<PlatformFile?> Function() _pickZipFile;
  final LegacyVaultFileOperations _files;
  final LegacyVaultZipCodec _codec;
  final LegacyVaultTransaction _transactions;
  final _rng = Random.secure();
  static Future<void> _tail = Future.value();
  static int _pending = 0;
  static int _epoch = 0;
  static int _scopedWipes = 0;
  static bool _fullWipe = false;
  static int _lastStamp = 0;

  static void suspendForDataWipe() {
    _fullWipe = true;
    _epoch++;
  }

  static Future<void> drainForDataWipe() =>
      _tail.timeout(const Duration(seconds: 30));

  static void resetWipeGateForTesting() {
    if (_pending != 0) throw StateError('Legacy operations have not drained.');
    _fullWipe = false;
    _scopedWipes = 0;
    _epoch++;
  }

  static Future<T> withDataWipe<T>(Future<T> Function() action) {
    _scopedWipes++;
    _epoch++;
    return _enqueue(action).whenComplete(() => _scopedWipes--);
  }

  static Future<T> _enqueue<T>(Future<T> Function() action) {
    _pending++;
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {
      _pending--;
    }, onError: (Object _, StackTrace __) {
      _pending--;
    });
    return result;
  }

  static void _admit(int epoch) {
    if (_fullWipe || _scopedWipes != 0 || epoch != _epoch) {
      throw const LegacyVaultZipException(
          'Vault operation was cancelled by local data removal.');
    }
  }

  Future<T> _withVault<T>(Future<T> Function(Directory, void Function()) action,
      {int? admittedEpoch}) {
    final epoch = admittedEpoch ?? _epoch;
    try {
      _admit(epoch);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    return _enqueue(() async {
      void checkpoint() => _admit(epoch);
      checkpoint();
      final vault = await _vaultDir();
      checkpoint();
      final leaseFile = await legacyVaultFile(vault, '.operation.lock');
      final lease = await leaseFile.open(mode: FileMode.append);
      try {
        await lease.lock(FileLock.blockingExclusive);
        checkpoint();
        try {
          await _transactions.recover(vault);
        } catch (_) {
          throw const LegacyVaultZipException(
              'Import recovery needs to finish before the vault can reopen.');
        }
        checkpoint();
        return await action(vault, checkpoint);
      } finally {
        await lease.close();
      }
    });
  }

  Future<Directory> _vaultDir() async {
    final docs = await _documents();
    if (!await docs.exists()) await docs.create(recursive: true);
    final root = Directory('${docs.path}/$_vaultFolder');
    var type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await root.create();
      type = await FileSystemEntity.type(root.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw const LegacyVaultZipException(
          'Vault root is blocked or contains a link.');
    }
    final base = (await docs.resolveSymbolicLinks()).replaceAll('\\', '/');
    final resolved = (await root.resolveSymbolicLinks()).replaceAll('\\', '/');
    if ((Platform.isWindows ? resolved.toLowerCase() : resolved) !=
        '${Platform.isWindows ? base.toLowerCase() : base}/$_vaultFolder') {
      throw const LegacyVaultZipException(
          'Vault root is outside application documents.');
    }
    return root;
  }

  String _stamp() {
    _lastStamp = max(_lastStamp + 1, DateTime.now().microsecondsSinceEpoch);
    return '$_lastStamp';
  }

  String newId() =>
      '${_stamp()}_${base64UrlEncode(List.generate(6, (_) => _rng.nextInt(256))).replaceAll('=', '')}';
  Future<Directory> vaultDirectory() => _withVault((vault, _) async => vault);

  Future<File> _capsuleFile(Directory vault, String id) {
    validateLegacyCapsuleId(id);
    return legacyVaultFile(vault, 'capsule_$id.json');
  }

  Future<Directory> _capsuleDir(Directory vault, String id,
      {bool attachments = false}) async {
    validateLegacyCapsuleId(id);
    final probe = await legacyVaultFile(
        vault, 'capsule_$id/${attachments ? 'attachments/' : ''}.probe',
        createParents: true);
    return probe.parent;
  }

  Future<Directory> capsuleDir(String id) =>
      _withVault((vault, _) => _capsuleDir(vault, id));
  Future<Directory> capsuleAttachmentDir(String id) =>
      _withVault((vault, _) => _capsuleDir(vault, id, attachments: true));
  Future<File> _attachment(Directory vault, String relative) {
    final normalized = normalizeLegacyRelativePath(relative);
    final first = normalized.split('/').first;
    if (!first.startsWith('capsule_')) {
      throw const LegacyVaultZipException('Invalid attachment reference.');
    }
    return legacyVaultFile(vault,
        legacyAttachmentPath(first.substring('capsule_'.length), normalized));
  }

  Future<File> resolveAttachmentFile(String relative) =>
      _withVault((vault, _) => _attachment(vault, relative));

  Future<List<LegacyCapsule>> _list(Directory vault,
      {bool strict = false}) async {
    final capsules = <LegacyCapsule>[];
    final ids = <String>{};
    await for (final entry in vault.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      if (!name.startsWith('capsule_') || !name.endsWith('.json')) continue;
      try {
        final file = await legacyVaultFile(vault, name);
        final capsule = _codec
            .readCapsule(await _files.read(file, _codec.limits.jsonBytes));
        if (name != 'capsule_${capsule.id}.json' ||
            !ids.add(capsule.id.toLowerCase())) {
          throw const LegacyVaultZipException(
              'Capsule identity conflicts with its file.');
        }
        capsules.add(capsule);
      } catch (_) {
        if (strict) {
          throw const LegacyVaultZipException(
              'A capsule record could not be backed up. Export stopped.');
        }
      }
    }
    capsules.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return capsules;
  }

  Future<List<LegacyCapsule>> listCapsules() =>
      _withVault((vault, _) => _list(vault));
  Future<LegacyCapsule?> _load(Directory vault, String id) async {
    final file = await _capsuleFile(vault, id);
    if (!await file.exists()) return null;
    return _codec.readCapsule(await _files.read(file, _codec.limits.jsonBytes));
  }

  Future<LegacyCapsule?> loadCapsule(String id) =>
      _withVault((vault, _) => _load(vault, id));

  Future<void> _save(Directory vault, LegacyCapsule capsule,
      void Function() checkpoint) async {
    for (final relative in capsule.attachments) {
      legacyAttachmentPath(capsule.id, relative);
    }
    final file = await _capsuleFile(vault, capsule.id);
    final temp =
        await legacyVaultFile(vault, 'capsule_${capsule.id}.${_stamp()}.tmp');
    final bytes = utf8.encode(capsule.toJson());
    if (bytes.length > _codec.limits.jsonBytes) {
      throw const LegacyVaultZipException(
          'Capsule metadata exceeds its limit.');
    }
    try {
      checkpoint();
      await _files.write(temp, bytes);
      checkpoint();
      await _files.renameFile(temp, file.path);
    } finally {
      if (await temp.exists()) await _files.deleteFile(temp);
    }
  }

  Future<LegacyCapsule> saveCapsule(LegacyCapsule capsule,
          {String? passphrase}) =>
      _withVault((vault, checkpoint) async {
        validateLegacyCapsuleId(capsule.id);
        var out = capsule.copyWith(updatedAt: DateTime.now());
        if (out.isEncrypted) {
          if (passphrase == null || passphrase.trim().isEmpty) {
            throw StateError('Passphrase required for encrypted capsules.');
          }
          final encrypted =
              await _encrypt(passphrase: passphrase, plaintext: capsule.body);
          out = out.copyWith(
              body: '',
              cipherTextB64: encrypted['cipherTextB64'] as String,
              nonceB64: encrypted['nonceB64'] as String,
              macB64: encrypted['macB64'] as String,
              saltB64: encrypted['saltB64'] as String);
        }
        await _save(vault, out, checkpoint);
        return out;
      });
  Future<void> deleteCapsule(String id) =>
      _withVault((vault, checkpoint) async {
        final file = await _capsuleFile(vault, id);
        final probe = await legacyVaultFile(vault, 'capsule_$id/.probe');
        checkpoint();
        await _files.deleteFile(file);
        await _files.deleteDirectory(probe.parent);
      });
  Future<String> importAttachment(
          {required String capsuleId, required PlatformFile source}) =>
      _withVault((vault, checkpoint) async {
        final dir = await _capsuleDir(vault, capsuleId, attachments: true);
        var name = source.name
            .replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_')
            .replaceAll(RegExp(r'[. ]+$'), '');
        if (name.isEmpty) name = 'attachment';
        final relative = 'capsule_$capsuleId/attachments/${_stamp()}_$name';
        legacyAttachmentPath(capsuleId, relative);
        final bytes = await readLegacyBounded(
            source.readAsByteStream(), _codec.limits.entryBytes);
        checkpoint();
        final target = File('${dir.path}/${relative.split('/').last}');
        try {
          await _files.write(target, bytes);
          checkpoint();
        } catch (_) {
          await _files.deleteFile(target);
          rethrow;
        }
        return relative;
      });
  Future<void> deleteAttachment({required String attachmentRelPath}) =>
      _withVault((vault, checkpoint) async {
        final file = await _attachment(vault, attachmentRelPath);
        checkpoint();
        await _files.deleteFile(file);
      });

  Future<LegacyCapsule> _exportBody(
      LegacyCapsule capsule, bool decrypt, String? passphrase) async {
    if (!decrypt || !capsule.isEncrypted) return capsule;
    if (passphrase == null || passphrase.trim().isEmpty) {
      throw StateError('Passphrase required for decrypted export.');
    }
    try {
      final body = await decryptBody(capsule: capsule, passphrase: passphrase);
      return capsule.copyWith(body: body, clearEncryption: true);
    } catch (_) {
      return capsule;
    }
  }

  Future<File> _writeZip(
      Map<String, List<int>> contents, String name, void Function() checkpoint,
      {bool wholeVault = false}) async {
    final bytes = _codec.encode(contents);
    if (wholeVault) await _codec.plan(bytes);
    checkpoint();
    final root = await _temporary();
    if (!await root.exists()) await root.create(recursive: true);
    final output = await legacyVaultFile(root, name);
    final partial = await legacyVaultFile(root, '$name.partial');
    try {
      await _files.write(partial, bytes);
      if (await legacyZipHash(
              await _files.read(partial, _codec.limits.archiveBytes)) !=
          await legacyZipHash(bytes)) {
        throw const LegacyVaultZipException(
            'Written export failed verification.');
      }
      checkpoint();
      if (await output.exists()) {
        throw const LegacyVaultZipException(
            'Export destination is already occupied.');
      }
      await _files.renameFile(partial, output.path);
      return output;
    } finally {
      if (await partial.exists()) await _files.deleteFile(partial);
    }
  }

  Future<LegacyVaultExportResult> exportVaultZipResult(
          {String? passphrase, bool decryptEncrypted = false}) =>
      _withVault((vault, checkpoint) async {
        final capsules = await _list(vault, strict: true);
        if (capsules.isEmpty || capsules.length > _codec.limits.capsules) {
          throw const LegacyVaultZipException(
              'Vault is empty or exceeds the capsule limit.');
        }
        final contents = <String, List<int>>{};
        var total = 0;
        var encrypted = 0;
        for (final capsule in capsules) {
          checkpoint();
          final out = await _exportBody(capsule, decryptEncrypted, passphrase);
          if (out.isEncrypted) encrypted++;
          final metadata = utf8.encode(out.toJson());
          if ((total += metadata.length) > _codec.limits.totalBytes) {
            throw const LegacyVaultZipException(
                'Backup exceeds its uncompressed byte limit.');
          }
          contents['capsules/capsule_${capsule.id}.json'] = metadata;
          final seen = <String>{};
          for (final relative in capsule.attachments) {
            final normalized = legacyAttachmentPath(capsule.id, relative);
            final entry =
                'attachments/${capsule.id}/${normalized.split('/').last}';
            if (!seen.add(entry.toLowerCase())) {
              throw const LegacyVaultZipException(
                  'Attachment names collide. Export stopped.');
            }
            final bytes = await _files.read(
                await _attachment(vault, normalized),
                min(_codec.limits.entryBytes,
                    _codec.limits.totalBytes - total));
            checkpoint();
            total += bytes.length;
            contents[entry] = bytes;
          }
        }
        contents['manifest.json'] = await _codec.makeManifest(contents);
        final output = await _writeZip(
            contents, 'neura_legacy_vault_export_${_stamp()}.zip', checkpoint,
            wholeVault: true);
        return LegacyVaultExportResult(output, encrypted,
            requestedDecryption: decryptEncrypted);
      });
  Future<File> exportVaultZip(
          {String? passphrase, bool decryptEncrypted = false}) async =>
      (await exportVaultZipResult(
              passphrase: passphrase, decryptEncrypted: decryptEncrypted))
          .file;
  Future<LegacyVaultImportResult> importVaultZipInteractiveResult() async {
    final epoch = _epoch;
    _admit(epoch);
    final file = await _pickZipFile();
    _admit(epoch);
    if (file == null) return const LegacyVaultImportResult(cancelled: true);
    return _withVault((vault, checkpoint) async {
      final bytes = await readLegacyBounded(
          file.readAsByteStream(), _codec.limits.archiveBytes);
      final plan = await _codec.plan(bytes);
      checkpoint();
      return _transactions.install(vault, plan, checkpoint);
    }, admittedEpoch: epoch);
  }

  Future<LegacyVaultImportResult> importVaultZipResult(File zipFile) =>
      _withVault((vault, checkpoint) async {
        if (!await zipFile.exists()) {
          throw const LegacyVaultZipException(
              'Selected backup no longer exists.');
        }
        final bytes = await _files.read(zipFile, _codec.limits.archiveBytes);
        final plan = await _codec.plan(bytes);
        checkpoint();
        return _transactions.install(vault, plan, checkpoint);
      });
  Future<int> importVaultZipInteractive() async =>
      (await importVaultZipInteractiveResult()).imported;
  Future<int> importVaultZip(File file) async =>
      (await importVaultZipResult(file)).imported;

  Future<File> exportCapsule(String id,
          {String? passphrase, bool decrypted = true}) =>
      _withVault((vault, checkpoint) async {
        final capsule = await _load(vault, id);
        if (capsule == null) throw StateError('Capsule not found.');
        var out = capsule;
        if (decrypted && capsule.isEncrypted) {
          if (passphrase == null || passphrase.trim().isEmpty) {
            throw StateError('Passphrase required for decrypted export.');
          }
          out = capsule.copyWith(
              body: await decryptBody(capsule: capsule, passphrase: passphrase),
              clearEncryption: true);
        }
        final file = await legacyVaultFile(vault, 'legacy_export_$id.json');
        final temp =
            await legacyVaultFile(vault, 'legacy_export_$id.${_stamp()}.tmp');
        try {
          await _files.write(temp, utf8.encode(out.toJson()));
          checkpoint();
          await _files.renameFile(temp, file.path);
        } finally {
          if (await temp.exists()) await _files.deleteFile(temp);
        }
        return file;
      });
  Future<File> exportCapsuleZip(String id,
          {String? passphrase, bool decrypted = false}) =>
      _withVault((vault, checkpoint) async {
        final capsule = await _load(vault, id);
        if (capsule == null) throw StateError('Capsule not found.');
        final out = await _exportBody(capsule, decrypted, passphrase);
        final contents = <String, List<int>>{
          'capsule.json': utf8.encode(out.toJson())
        };
        contents['README.txt'] = utf8.encode(
            'Neura Companion — Legacy Delivery Packet\n'
            '${out.isEncrypted ? 'The capsule body remains encrypted; its passphrase is required.' : 'The capsule body is plaintext.'}\n'
            'Attachment bytes and metadata are not encrypted by the capsule body encryption.\n'
            'This is a delivery packet, not a whole-vault restore bundle.\n');
        try {
          contents['cover.pdf'] =
              await LegacyPdfCoverBuilder.buildCover(capsule: out);
        } catch (_) {/* optional cover only */}
        var total = contents.values.fold<int>(0, (n, b) => n + b.length);
        final names = <String>{};
        for (final relative in capsule.attachments) {
          final normalized = legacyAttachmentPath(id, relative);
          final name = normalized.split('/').last;
          if (!names.add(name.toLowerCase())) {
            throw const LegacyVaultZipException(
                'Delivery attachment names collide.');
          }
          final bytes = await _files.read(await _attachment(vault, normalized),
              min(_codec.limits.entryBytes, _codec.limits.totalBytes - total));
          total += bytes.length;
          contents['attachments/$name'] = bytes;
          checkpoint();
        }
        return _writeZip(
            contents, 'legacy_packet_${id}_${_stamp()}.zip', checkpoint);
      });
  Future<LegacyCapsule> duplicateCapsule(String id) =>
      _withVault((vault, checkpoint) async {
        final capsule = await _load(vault, id);
        if (capsule == null) throw StateError('Capsule not found.');
        final newId = this.newId();
        final attachments = <String>[];
        try {
          for (final relative in capsule.attachments) {
            final source =
                await _attachment(vault, legacyAttachmentPath(id, relative));
            final path =
                'capsule_$newId/attachments/${_stamp()}_${normalizeLegacyRelativePath(relative).split('/').last}';
            final target =
                await legacyVaultFile(vault, path, createParents: true);
            final bytes = await _files.read(source, _codec.limits.entryBytes);
            checkpoint();
            await _files.write(target, bytes);
            attachments.add(path);
          }
          final now = DateTime.now();
          final duplicate = capsule.copyWith(
              id: newId,
              createdAt: now,
              updatedAt: now,
              isSealed: false,
              attachments: attachments);
          await _save(vault, duplicate, checkpoint);
          return duplicate;
        } catch (_) {
          await _files
              .deleteDirectory(Directory('${vault.path}/capsule_$newId'));
          rethrow;
        }
      });

  Future<String> decryptBody({
    required LegacyCapsule capsule,
    required String passphrase,
  }) async {
    if (!capsule.isEncrypted) return capsule.body;
    if (capsule.cipherTextB64 == null ||
        capsule.nonceB64 == null ||
        capsule.macB64 == null ||
        capsule.saltB64 == null) {
      throw StateError('Encrypted capsule is missing crypto fields.');
    }

    final salt = base64Decode(capsule.saltB64!);
    final nonce = base64Decode(capsule.nonceB64!);
    final cipherText = base64Decode(capsule.cipherTextB64!);
    final macBytes = base64Decode(capsule.macB64!);

    final key = await _deriveKey(passphrase: passphrase, salt: salt);
    final aes = AesGcm.with256bits();
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    final clear = await aes.decrypt(secretBox, secretKey: key);
    return utf8.decode(clear);
  }

  Future<Map<String, Object>> _encrypt({
    required String passphrase,
    required String plaintext,
  }) async {
    final salt = List<int>.generate(16, (_) => _rng.nextInt(256));
    final nonce = List<int>.generate(12, (_) => _rng.nextInt(256));
    final key = await _deriveKey(passphrase: passphrase, salt: salt);

    final aes = AesGcm.with256bits();
    final secretBox = await aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );

    return {
      'cipherTextB64': base64Encode(secretBox.cipherText),
      'nonceB64': base64Encode(secretBox.nonce),
      'macB64': base64Encode(secretBox.mac.bytes),
      'saltB64': base64Encode(salt),
    };
  }

  Future<SecretKey> _deriveKey({
    required String passphrase,
    required List<int> salt,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }
}
