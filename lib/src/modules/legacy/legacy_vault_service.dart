import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'legacy_pdf_cover_builder.dart';

import 'models/legacy_capsule.dart';

/// Local-only vault for Legacy Capsules.
///
/// Storage layout (app documents):
///   neura_legacy_vault/
///     capsule_ID.json
///     capsule_ID/attachments/*
class LegacyVaultService {
  LegacyVaultService._();

  static final LegacyVaultService instance = LegacyVaultService._();

  static const _vaultFolder = 'neura_legacy_vault';

  final _rng = Random.secure();

  Future<Directory> _vaultDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_vaultFolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Exposed for UI helpers (sharing/opening attachments, etc.).
  Future<Directory> vaultDirectory() => _vaultDir();

  Future<File> resolveAttachmentFile(String attachmentRelPath) async {
    final vault = await _vaultDir();
    final norm = attachmentRelPath.replaceAll('\\', '/');
    return File('${vault.path}/$norm');
  }

  String newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toString();
    final r = List<int>.generate(6, (_) => _rng.nextInt(256));
    final rb64 = base64UrlEncode(r).replaceAll('=', '');
    return '${t}_$rb64';
  }

  Future<File> _capsuleFile(String id) async {
    final dir = await _vaultDir();
    return File('${dir.path}/capsule_$id.json');
  }

  Future<Directory> capsuleDir(String id) async {
    final dir = await _vaultDir();
    final d = Directory('${dir.path}/capsule_$id');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  Future<Directory> capsuleAttachmentDir(String id) async {
    final d = await capsuleDir(id);
    final a = Directory('${d.path}/attachments');
    if (!await a.exists()) await a.create(recursive: true);
    return a;
  }

  Future<List<LegacyCapsule>> listCapsules() async {
    final dir = await _vaultDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json') && f.path.contains('capsule_'))
        .toList();

    final out = <LegacyCapsule>[];
    for (final f in files) {
      try {
        final raw = await f.readAsString();
        out.add(LegacyCapsule.fromJson(raw));
      } catch (_) {
        // Skip corrupted entries.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<LegacyCapsule?> loadCapsule(String id) async {
    final f = await _capsuleFile(id);
    if (!await f.exists()) return null;
    final raw = await f.readAsString();
    return LegacyCapsule.fromJson(raw);
  }

  Future<LegacyCapsule> saveCapsule(
    LegacyCapsule capsule, {
    String? passphrase,
  }) async {
    final now = DateTime.now();
    LegacyCapsule toWrite = capsule.copyWith(updatedAt: now);

    if (toWrite.isEncrypted) {
      if (passphrase == null || passphrase.trim().isEmpty) {
        throw StateError('Passphrase required for encrypted capsules.');
      }
      final enc =
          await _encrypt(passphrase: passphrase, plaintext: capsule.body);
      toWrite = toWrite.copyWith(
        body: '',
        cipherTextB64: enc['cipherTextB64'] as String,
        nonceB64: enc['nonceB64'] as String,
        macB64: enc['macB64'] as String,
        saltB64: enc['saltB64'] as String,
      );
    }

    final f = await _capsuleFile(toWrite.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(toWrite.toJson());
    await tmp.rename(f.path);
    return toWrite;
  }

  Future<void> deleteCapsule(String id) async {
    final f = await _capsuleFile(id);
    if (await f.exists()) {
      await f.delete();
    }
    final d = await capsuleDir(id);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Copy a user-selected file into this capsule's attachments folder.
  /// Returns a **relative** path (relative to the vault root) to store in the capsule model.
  Future<String> importAttachment({
    required String capsuleId,
    required String sourcePath,
  }) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw StateError('Attachment file not found.');
    }

    final attachDir = await capsuleAttachmentDir(capsuleId);
    final baseName = sourcePath.split(Platform.pathSeparator).last;
    final safeName = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');

    // Avoid collisions.
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final outName = '${stamp}_$safeName';
    final out = File('${attachDir.path}/$outName');
    await src.copy(out.path);

    final vault = await _vaultDir();
    final rel =
        out.path.replaceFirst('${vault.path}${Platform.pathSeparator}', '');
    return rel;
  }

  Future<void> deleteAttachment({
    required String attachmentRelPath,
  }) async {
    final vault = await _vaultDir();
    final file =
        File('${vault.path}/${attachmentRelPath.replaceAll('\\', '/')}');
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Export the **entire** Legacy Vault as a single .zip bundle.
  ///
  /// Notes:
  /// - Encrypted capsules are exported **as-is** unless [decryptEncrypted] is true.
  /// - If decrypting, this assumes a shared passphrase for all encrypted capsules.
  Future<File> exportVaultZip({
    String? passphrase,
    bool decryptEncrypted = false,
  }) async {
    final temp = await getTemporaryDirectory();
    final out = File(
        '${temp.path}/neura_legacy_vault_export_${DateTime.now().millisecondsSinceEpoch}.zip');

    final vault = await _vaultDir();
    final archive = Archive();

    final capsules = await listCapsules();
    for (final c in capsules) {
      LegacyCapsule toWrite = c;
      if (decryptEncrypted && c.isEncrypted) {
        if (passphrase == null || passphrase.trim().isEmpty) {
          throw StateError(
              'Passphrase required to decrypt encrypted capsules.');
        }
        try {
          final body = await decryptBody(capsule: c, passphrase: passphrase);
          toWrite = c.copyWith(
            body: body,
            isEncrypted: false,
            cipherTextB64: null,
            nonceB64: null,
            macB64: null,
            saltB64: null,
          );
        } catch (_) {
          // If decrypt fails, fall back to exporting raw encrypted capsule.
          toWrite = c;
        }
      }

      final jsonBytes = utf8.encode(toWrite.toJson());
      archive.addFile(ArchiveFile(
          'capsules/capsule_${c.id}.json', jsonBytes.length, jsonBytes));

      // Attachments
      for (final rel in c.attachments) {
        final p = '${vault.path}/${rel.replaceAll('\\', '/')}';
        final f = File(p);
        if (!await f.exists()) continue;
        final bytes = await f.readAsBytes();
        archive.addFile(ArchiveFile(
            'attachments/${c.id}/${f.uri.pathSegments.last}',
            bytes.length,
            bytes));
      }
    }

    final zipped = ZipEncoder().encode(archive);
    await out.writeAsBytes(zipped, flush: true);
    return out;
  }

  /// Optional: pick a .zip export and import it back into the local vault.
  /// This is conservative: it will **not** overwrite existing capsule IDs.
  Future<int> importVaultZipInteractive() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return 0;
    final path = result.files.single.path;
    if (path == null) return 0;
    return importVaultZip(File(path));
  }

  /// Import from a previously exported zip.
  Future<int> importVaultZip(File zipFile) async {
    if (!await zipFile.exists()) return 0;
    final bytes = await zipFile.readAsBytes();
    final decoded = ZipDecoder().decodeBytes(bytes);

    final vault = await _vaultDir();
    int imported = 0;

    // First pass: capsules JSON.
    for (final f in decoded.files) {
      if (!f.isFile) continue;
      if (!f.name.startsWith('capsules/') || !f.name.endsWith('.json')) {
        continue;
      }

      final raw = utf8.decode(f.content as List<int>);
      final capsule = LegacyCapsule.fromJson(raw);

      final dst = File('${vault.path}/capsule_${capsule.id}.json');
      if (await dst.exists()) {
        // Never overwrite.
        continue;
      }
      await dst.writeAsString(capsule.toJson(), flush: true);
      imported++;
    }

    // Second pass: attachments.
    for (final f in decoded.files) {
      if (!f.isFile) continue;
      if (!f.name.startsWith('attachments/')) continue;
      // attachments/<id>/<filename>
      final parts = f.name.split('/');
      if (parts.length < 3) continue;
      final id = parts[1];
      final name = parts.sublist(2).join('_');
      final attachDir = await capsuleAttachmentDir(id);
      final dst = File('${attachDir.path}/$name');
      if (await dst.exists()) continue;
      await dst.writeAsBytes(f.content as List<int>, flush: true);
    }

    return imported;
  }

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

  Future<File> exportCapsule(
    String id, {
    String? passphrase,
    bool decrypted = true,
  }) async {
    final capsule = await loadCapsule(id);
    if (capsule == null) {
      throw StateError('Capsule not found.');
    }

    LegacyCapsule out = capsule;
    if (decrypted && capsule.isEncrypted) {
      if (passphrase == null || passphrase.trim().isEmpty) {
        throw StateError('Passphrase required to export decrypted capsule.');
      }
      final body = await decryptBody(capsule: capsule, passphrase: passphrase);
      out = capsule.copyWith(
        body: body,
        isEncrypted: false,
        cipherTextB64: null,
        nonceB64: null,
        macB64: null,
        saltB64: null,
      );
    }

    final dir = await _vaultDir();
    final file = File('${dir.path}/legacy_export_$id.json');
    await file.writeAsString(out.toJson());
    return file;
  }

  /// Export a **single** capsule as a delivery-friendly .zip.
  ///
  /// The zip includes:
  /// - capsule.json (optionally decrypted)
  /// - attachments/* (copied as-is)
  /// - README.txt
  Future<File> exportCapsuleZip(
    String id, {
    String? passphrase,
    bool decrypted = false,
  }) async {
    final capsule = await loadCapsule(id);
    if (capsule == null) {
      throw StateError('Capsule not found.');
    }

    LegacyCapsule out = capsule;
    if (decrypted && capsule.isEncrypted) {
      if (passphrase == null || passphrase.trim().isEmpty) {
        throw StateError('Passphrase required to export decrypted capsule.');
      }
      try {
        final body =
            await decryptBody(capsule: capsule, passphrase: passphrase);
        out = capsule.copyWith(
          body: body,
          isEncrypted: false,
          cipherTextB64: null,
          nonceB64: null,
          macB64: null,
          saltB64: null,
        );
      } catch (_) {
        // If decrypt fails, fall back to encrypted export.
        out = capsule;
      }
    }

    final archive = Archive();

    final capsuleBytes = utf8.encode(out.toJson());
    archive.addFile(
        ArchiveFile('capsule.json', capsuleBytes.length, capsuleBytes));

    final readme = 'Neura Companion — Legacy Delivery Packet\n'
        '------------------------------------------------\n\n'
        'This packet contains a single Legacy Capsule and its attachments.\n'
        'If the capsule is encrypted, you will need the passphrase to read it.\n\n'
        'Inside: \n'
        '- capsule.json\n'
        '- attachments/ (optional)\n\n'
        'Generated: ${DateTime.now().toLocal()}\n';

    final readmeBytes = utf8.encode(readme);
    archive.addFile(ArchiveFile('README.txt', readmeBytes.length, readmeBytes));

    // Pretty cover page (PDF) for humans.
    try {
      final coverBytes = await LegacyPdfCoverBuilder.buildCover(capsule: out);
      archive.addFile(ArchiveFile('cover.pdf', coverBytes.length, coverBytes));
    } catch (_) {
      // best-effort
    }

    // Attachments
    for (final rel in capsule.attachments) {
      try {
        final file = await resolveAttachmentFile(rel);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final name = rel.split('/').last;
        archive.addFile(ArchiveFile('attachments/$name', bytes.length, bytes));
      } catch (_) {
        // best-effort
      }
    }

    final temp = await getTemporaryDirectory();
    final outFile = File(
        '${temp.path}/legacy_packet_${id}_${DateTime.now().millisecondsSinceEpoch}.zip');
    final encoded = ZipEncoder().encode(archive);
    await outFile.writeAsBytes(encoded, flush: true);
    return outFile;
  }

  /// Duplicate a capsule (including attachments) so a sealed capsule can be edited safely.
  ///
  /// - The duplicate is **not** sealed.
  /// - Encryption status is preserved.
  Future<LegacyCapsule> duplicateCapsule(String id) async {
    final src = await loadCapsule(id);
    if (src == null) {
      throw StateError('Capsule not found.');
    }

    final now = DateTime.now();
    final newId = this.newId();

    final vault = await _vaultDir();
    final attachDir = await capsuleAttachmentDir(newId);

    final newAttachments = <String>[];
    for (final rel in src.attachments) {
      try {
        final srcFile = File('${vault.path}/${rel.replaceAll('\\\\', '/')}');
        if (!await srcFile.exists()) continue;
        final baseName = srcFile.path.split(Platform.pathSeparator).last;
        final stamp = DateTime.now().microsecondsSinceEpoch.toString();
        final outFile = File('${attachDir.path}/${stamp}_$baseName');
        await srcFile.copy(outFile.path);

        final relOut = outFile.path
            .replaceFirst('${vault.path}${Platform.pathSeparator}', '');
        newAttachments.add(relOut);
      } catch (_) {
        // best-effort
      }
    }

    final dup = src.copyWith(
      id: newId,
      createdAt: now,
      updatedAt: now,
      isSealed: false,
      attachments: newAttachments,
    );

    final f = await _capsuleFile(newId);
    await f.writeAsString(dup.toJson(), flush: true);
    return dup;
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
