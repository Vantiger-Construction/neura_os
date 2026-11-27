import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide Sha256;
import 'package:cryptography/cryptography.dart' show Sha256;

import 'models/legacy_capsule.dart';

/// A refusal is explicit; limits never silently truncate a backup.
class LegacyVaultZipException implements Exception {
  const LegacyVaultZipException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Conservative in-memory budgets, not a Windows performance certification.
class LegacyVaultZipLimits {
  const LegacyVaultZipLimits({
    this.archiveBytes = 128 * 1024 * 1024,
    this.entryBytes = 64 * 1024 * 1024,
    this.totalBytes = 128 * 1024 * 1024,
    this.jsonBytes = 1024 * 1024,
    this.entries = 4096,
    this.capsules = 512,
  });

  final int archiveBytes;
  final int entryBytes;
  final int totalBytes;
  final int jsonBytes;
  final int entries;
  final int capsules;

  void validate() {
    final values = [
      archiveBytes,
      entryBytes,
      totalBytes,
      jsonBytes,
      entries,
      capsules
    ];
    final maxima = [
      128 * 1024 * 1024,
      64 * 1024 * 1024,
      128 * 1024 * 1024,
      1024 * 1024,
      4096,
      512
    ];
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0 || values[i] > maxima[i]) {
        throw ArgumentError(
            'Legacy ZIP budgets must be positive and within the supported restore limits.');
      }
    }
  }
}

Future<String> legacyZipHash(List<int> bytes) async =>
    (await Sha256().hash(bytes))
        .bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

void validateLegacyCapsuleId(String id) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(id)) {
    throw const LegacyVaultZipException('Invalid capsule identifier.');
  }
}

void validateLegacyPathPart(String part) {
  if (part.isEmpty ||
      part == '.' ||
      part == '..' ||
      part.endsWith('.') ||
      part.endsWith(' ') ||
      utf8.encode(part).length > 255 ||
      RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*]').hasMatch(part) ||
      RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
              caseSensitive: false)
          .hasMatch(part)) {
    throw const LegacyVaultZipException('Unsafe or unsupported file name.');
  }
}

String normalizeLegacyRelativePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  for (final part in normalized.split('/')) {
    validateLegacyPathPart(part);
  }
  return normalized;
}

String legacyAttachmentPath(String id, String relative) {
  validateLegacyCapsuleId(id);
  final normalized = normalizeLegacyRelativePath(relative);
  final parts = normalized.split('/');
  if (parts.length != 3 ||
      parts[0] != 'capsule_$id' ||
      parts[1] != 'attachments') {
    throw const LegacyVaultZipException(
        'Attachment reference does not belong to its capsule.');
  }
  return normalized;
}

class LegacyVaultZipPlan {
  const LegacyVaultZipPlan(this.capsules, this.files);
  final List<LegacyCapsule> capsules;

  /// Destination-relative paths; contents have already passed CRC validation.
  final Map<String, List<int>> files;
}

/// Pure codec: no file access, credentials, user stores or Flutter plugins.
class LegacyVaultZipCodec {
  const LegacyVaultZipCodec({this.limits = const LegacyVaultZipLimits()});
  final LegacyVaultZipLimits limits;

  Archive decode(List<int> bytes) {
    limits.validate();
    if (bytes.length > limits.archiveBytes) {
      throw const LegacyVaultZipException(
          'ZIP exceeds the restore byte limit.');
    }
    try {
      final directory = _checkDirectory(bytes);
      // Normalize only EOCD comment/trailing metadata for the 4.6.0 reader.
      // Member bytes, offsets and CRCs remain unchanged.
      List<int> input = bytes;
      if (directory.end != bytes.length ||
          bytes[directory.end - 2] != 0 ||
          bytes[directory.end - 1] != 0) {
        final canonical = Uint8List.fromList(bytes.sublist(0, directory.end));
        canonical[directory.end - 2] = 0;
        canonical[directory.end - 1] = 0;
        input = canonical;
      }
      final decoder = ZipDecoder();
      final archive =
          decoder.decodeBytes(input, verify: true, throwOnError: true);
      final names = <String>{};
      for (final header in decoder.directory.fileHeaders) {
        final name = header.filename.replaceAll('\\', '/');
        final trimmed =
            name.endsWith('/') ? name.substring(0, name.length - 1) : name;
        normalizeLegacyRelativePath(trimmed);
        if (!names.add(trimmed.toLowerCase())) {
          throw const LegacyVaultZipException(
              'ZIP contains duplicate or colliding entry names.');
        }
      }
      if (archive.files.length != directory.count) {
        throw const LegacyVaultZipException('ZIP directory is inconsistent.');
      }
      final decodedNames = <String>{};
      for (var index = 0; index < archive.files.length; index++) {
        final file = archive.files[index];
        final name = file.name.replaceAll('\\', '/');
        final trimmed =
            name.endsWith('/') ? name.substring(0, name.length - 1) : name;
        normalizeLegacyRelativePath(trimmed);
        if (!decodedNames.add(trimmed.toLowerCase()) ||
            name !=
                decoder.directory.fileHeaders[index].filename
                    .replaceAll('\\', '/')) {
          throw const LegacyVaultZipException(
              'ZIP local and directory names conflict.');
        }
        if (file.isSymbolicLink) {
          throw const LegacyVaultZipException('ZIP links are not supported.');
        }
        if (file.isFile && file.content.length != file.size) {
          throw const LegacyVaultZipException('ZIP entry is incomplete.');
        }
      }
      return archive;
    } on LegacyVaultZipException {
      rethrow;
    } catch (_) {
      // Do not include archive contents, filenames or platform paths in errors.
      throw const LegacyVaultZipException('ZIP is damaged or unsupported.');
    }
  }

  /// Check count/size budgets before ZipDecoder allocates or inflates entries.
  /// Legacy exports below these limits need neither ZIP64 nor split disks.
  ({int count, int end}) _checkDirectory(List<int> bytes) {
    int u16(int at) => bytes[at] | (bytes[at + 1] << 8);
    int u32(int at) => u16(at) | (u16(at + 2) << 16);
    int? directory;
    int? directoryEnd;
    int? expectedCount;
    for (var at = bytes.length - 22; at >= 0; at--) {
      if (u32(at) != 0x06054b50) continue;
      final end = at + 22 + u16(at + 20);
      final size = u32(at + 12);
      final start = u32(at + 16);
      if (end > bytes.length || start + size != at) continue;
      if (u16(at + 4) != 0 ||
          u16(at + 6) != 0 ||
          u16(at + 8) != u16(at + 10) ||
          u16(at + 10) == 0xffff) {
        throw const LegacyVaultZipException(
            'Split or ZIP64 backups require a separate restore tool.');
      }
      directory = start;
      directoryEnd = at;
      expectedCount = u16(at + 10);
      break;
    }
    if (directory == null || directoryEnd == null || expectedCount == null) {
      throw const LegacyVaultZipException('ZIP directory is missing or cut.');
    }
    if (expectedCount > limits.entries) {
      throw const LegacyVaultZipException('ZIP contains too many entries.');
    }
    var at = directory;
    var count = 0;
    var total = 0;
    final rawNames = <String>{};
    while (at < directoryEnd) {
      if (at + 46 > directoryEnd || u32(at) != 0x02014b50) {
        throw const LegacyVaultZipException('ZIP directory is damaged.');
      }
      final compressed = u32(at + 20);
      final size = u32(at + 24);
      final nameLength = u16(at + 28);
      final next = at + 46 + nameLength + u16(at + 30) + u16(at + 32);
      final offset = u32(at + 42);
      final method = u16(at + 10);
      final mode = u32(at + 38) >> 16;
      if (++count > limits.entries ||
          size > limits.entryBytes ||
          (total += size) > limits.totalBytes) {
        throw const LegacyVaultZipException(
            'ZIP exceeds the entry or uncompressed byte limit.');
      }
      if (next > directoryEnd ||
          nameLength == 0 ||
          offset + 30 > directory ||
          compressed > limits.archiveBytes ||
          u32(offset) != 0x04034b50 ||
          offset + 30 + u16(offset + 26) + u16(offset + 28) + compressed >
              directory ||
          u16(at + 34) != 0 ||
          u16(at + 8) & 1 != 0 ||
          (method != 0 && method != 8) ||
          mode & 0xf000 == 0xa000) {
        throw const LegacyVaultZipException(
            'ZIP has unsafe or unsupported entries.');
      }
      // ZipDecoder uses the directory's name/sizes but the local method and
      // flags. Validate both views before allowing it to decode any content.
      if (u16(offset + 6) != u16(at + 8) ||
          u16(offset + 8) != method ||
          u16(offset + 26) != nameLength ||
          (u16(at + 8) & 8 == 0 &&
              (u32(offset + 14) != u32(at + 16) ||
                  u32(offset + 18) != compressed ||
                  u32(offset + 22) != size))) {
        throw const LegacyVaultZipException(
            'ZIP local and directory headers conflict.');
      }
      for (var index = 0; index < nameLength; index++) {
        if (bytes[offset + 30 + index] != bytes[at + 46 + index]) {
          throw const LegacyVaultZipException(
              'ZIP local and directory names conflict.');
        }
      }
      if (!rawNames
          .add(base64Encode(bytes.sublist(at + 46, at + 46 + nameLength)))) {
        throw const LegacyVaultZipException(
            'ZIP contains duplicate entry names.');
      }
      at = next;
    }
    if (at != directoryEnd || count != expectedCount) {
      throw const LegacyVaultZipException('ZIP entry count is inconsistent.');
    }
    return (count: count, end: directoryEnd + 22);
  }

  LegacyCapsule readCapsule(List<int> bytes) {
    if (bytes.length > limits.jsonBytes) {
      throw const LegacyVaultZipException(
          'Capsule metadata exceeds its limit.');
    }
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic> ||
          value['id'] is! String ||
          value['createdAt'] is! String ||
          value['updatedAt'] is! String ||
          DateTime.tryParse(value['createdAt'] as String) == null ||
          DateTime.tryParse(value['updatedAt'] as String) == null) {
        throw const FormatException();
      }
      for (final key in ['title', 'body']) {
        if (value[key] != null && value[key] is! String) {
          throw const FormatException();
        }
      }
      for (final key in ['isEncrypted', 'isSealed', 'deliveryEnabled']) {
        if (value[key] != null && value[key] is! bool) {
          throw const FormatException();
        }
      }
      for (final key in [
        'attachments',
        'tags',
        'recipients',
        'deliveryContactIds'
      ]) {
        final list = value[key];
        if (list != null &&
            (list is! List ||
                list.length > limits.entries ||
                list.any((item) => item is! String))) {
          throw const FormatException();
        }
      }
      final capsule = LegacyCapsule.fromMap(value);
      validateLegacyCapsuleId(capsule.id);
      if (capsule.isEncrypted) {
        if (capsule.body.isNotEmpty ||
            base64Decode(capsule.saltB64!).length != 16 ||
            base64Decode(capsule.nonceB64!).length != 12 ||
            base64Decode(capsule.macB64!).length != 16) {
          throw const FormatException();
        }
        base64Decode(capsule.cipherTextB64!);
      }
      return capsule;
    } catch (_) {
      throw const LegacyVaultZipException('Invalid capsule metadata.');
    }
  }

  Future<LegacyVaultZipPlan> plan(List<int> bytes) async {
    final archive = decode(bytes);
    final sourceFiles = <String, List<int>>{};
    final capsules = <String, LegacyCapsule>{};
    List<int>? manifest;
    for (final file in archive.files) {
      final name = file.name.replaceAll('\\', '/');
      if (!file.isFile) continue;
      if (name == 'manifest.json') {
        manifest = file.content;
      } else {
        sourceFiles[name] = file.content;
      }
      if (name.startsWith('capsules/') &&
          name.split('/').length == 2 &&
          name.endsWith('.json')) {
        final capsule = readCapsule(file.content);
        if (capsules.containsKey(capsule.id.toLowerCase())) {
          throw const LegacyVaultZipException(
              'ZIP contains duplicate capsule IDs.');
        }
        capsules[capsule.id.toLowerCase()] = capsule;
        if (capsules.length > limits.capsules) {
          throw const LegacyVaultZipException(
              'ZIP contains too many capsules.');
        }
      } else if (name != 'manifest.json' && !name.startsWith('attachments/')) {
        throw const LegacyVaultZipException(
            'This ZIP is not a whole-vault backup. Delivery packets cannot be restored here.');
      }
    }
    if (capsules.isEmpty) {
      throw const LegacyVaultZipException(
          'Backup contains no capsule records.');
    }
    final files = <String, List<int>>{};
    final expectedAttachments = <String>{};
    for (final capsule in capsules.values) {
      final references = <String>{};
      for (final relative in capsule.attachments) {
        final destination = legacyAttachmentPath(capsule.id, relative);
        if (!references.add(destination.toLowerCase())) {
          throw const LegacyVaultZipException(
              'Duplicate attachment reference.');
        }
        final name = destination.split('/').last;
        final source = 'attachments/${capsule.id}/$name';
        final content = sourceFiles[source];
        if (content == null) {
          throw const LegacyVaultZipException(
              'Backup is missing a referenced attachment.');
        }
        expectedAttachments.add(source);
        files[destination] = content;
      }
      files['capsule_${capsule.id}.json'] = utf8.encode(capsule.toJson());
    }
    for (final name
        in sourceFiles.keys.where((name) => name.startsWith('attachments/'))) {
      if (!expectedAttachments.contains(name)) {
        throw const LegacyVaultZipException(
            'Backup contains orphan or unreferenced attachments.');
      }
    }
    if (manifest != null) await verifyManifest(manifest, sourceFiles);
    return LegacyVaultZipPlan(capsules.values.toList(), files);
  }

  Future<List<int>> makeManifest(Map<String, List<int>> files) async {
    final entries = <String, dynamic>{};
    for (final entry in files.entries) {
      entries[entry.key] = {
        'size': entry.value.length,
        'sha256': await legacyZipHash(entry.value)
      };
    }
    return utf8.encode(jsonEncode(
        {'format': 'neura-legacy-vault', 'version': 1, 'entries': entries}));
  }

  Future<void> verifyManifest(
      List<int> bytes, Map<String, List<int>> files) async {
    try {
      if (bytes.length > limits.jsonBytes) throw const FormatException();
      final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (manifest['format'] != 'neura-legacy-vault' ||
          manifest['version'] != 1) {
        throw const FormatException();
      }
      final entries = manifest['entries'] as Map<String, dynamic>;
      if (entries.length != files.length) throw const FormatException();
      for (final file in files.entries) {
        final expected = entries[file.key] as Map;
        if (expected['size'] != file.value.length ||
            expected['sha256'] != await legacyZipHash(file.value)) {
          throw const FormatException();
        }
      }
    } catch (_) {
      throw const LegacyVaultZipException(
          'Backup manifest does not match its contents.');
    }
  }

  List<int> encode(Map<String, List<int>> files) {
    limits.validate();
    var total = 0;
    if (files.length > limits.entries) {
      throw const LegacyVaultZipException('Backup contains too many files.');
    }
    final archive = Archive();
    for (final entry in files.entries) {
      if (entry.value.length > limits.entryBytes ||
          (total += entry.value.length) > limits.totalBytes) {
        throw const LegacyVaultZipException(
            'Backup exceeds the uncompressed byte limit.');
      }
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final bytes = ZipEncoder().encode(archive);
    if (bytes.length > limits.archiveBytes) {
      throw const LegacyVaultZipException('Backup exceeds the ZIP byte limit.');
    }
    decode(
        bytes); // Validate every encoded member before admitting an output file.
    return bytes;
  }
}
