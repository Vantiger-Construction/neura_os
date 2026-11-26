import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide Sha256;
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/src/modules/legacy/legacy_vault_service.dart';
import 'package:neuro_companion/src/modules/legacy/legacy_vault_transaction.dart';
import 'package:neuro_companion/src/modules/legacy/legacy_vault_zip_codec.dart';
import 'package:neuro_companion/src/modules/legacy/models/legacy_capsule.dart';
import 'package:path/path.dart' as p;

const fictionalPassphrase = 'Fictional Archive Kit Only 2026!';
const fictionalSecret = 'Fictional Rowan saved a note about a blue paper moon.';

LegacyCapsule fictionalCapsule(String id,
        {List<String> attachments = const []}) =>
    LegacyCapsule(
      id: id,
      title: 'Fictional $id',
      body: 'Fictional paper moon.',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      attachments: attachments,
    );

List<int> fictionalZip(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encode(archive);
}

class LegacyZipFixture {
  LegacyZipFixture._(this.root);
  final Directory root;
  Directory get documents => Directory('${root.path}/documents');
  Directory get temporary => Directory('${root.path}/temporary');
  Directory get vault => Directory('${documents.path}/neura_legacy_vault');
  final escapedPaths = <String>[];

  static Future<LegacyZipFixture> create() async {
    LegacyVaultService.resetWipeGateForTesting();
    final root = await Directory.systemTemp.createTemp('neura-fictional-zip-');
    final fixture = LegacyZipFixture._(root);
    await fixture.documents.create();
    await fixture.temporary.create();
    await File('${root.path}/SYNTHETIC_ONLY')
        .writeAsString('FICTIONAL LEGACY ZIP TEST');
    addTearDown(() async {
      await LegacyVaultService.drainForDataWipe();
      LegacyVaultService.resetWipeGateForTesting();
      if (await root.exists()) await root.delete(recursive: true);
      expect(fixture.escapedPaths, isEmpty,
          reason: 'No operation may access an installed vault.');
    });
    return fixture;
  }

  LegacyVaultService service(
          {LegacyVaultFileOperations files = const LegacyVaultFileOperations(),
          LegacyVaultZipLimits limits = const LegacyVaultZipLimits(),
          Future<PlatformFile?> Function()? pickZipFile}) =>
      LegacyVaultService(
        documentsDirectory: () async => documents,
        temporaryDirectory: () async => temporary,
        files: files,
        limits: limits,
        pickZipFile: pickZipFile,
      );

  Future<File> archive(String version, String name) async {
    if (!['4.6.0', '4.7.1'].contains(version) ||
        !RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
      throw ArgumentError('Fixture identifier');
    }
    final source = File(
        'test/legacy/fixtures/archive_${version.replaceAll('.', '_')}/$name.zip');
    return source.copy('${root.path}/${version}_$name.zip');
  }

  Future<File> zip(List<int> bytes, {String name = 'fictional.zip'}) async {
    final file = File('${root.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  String _guard(String path) {
    final absolute = p.normalize(p.absolute(path));
    if (!p.equals(absolute, root.path) && !p.isWithin(root.path, absolute)) {
      escapedPaths.add(path);
      throw StateError(
          'Filesystem operation escaped the fictional ZIP fixture.');
    }
    return path;
  }

  Future<T> run<T>(Future<T> Function() action) {
    final outer = Zone.current;
    return HttpOverrides.runZoned(
        () => IOOverrides.runZoned(
              action,
              createFile: (path) => outer.run(() => File(_guard(path))),
              createDirectory: (path) =>
                  outer.run(() => Directory(_guard(path))),
              createLink: (path) => outer.run(() => Link(_guard(path))),
              fseGetType: (path, follow) => outer.run(() =>
                  FileSystemEntity.type(_guard(path), followLinks: follow)),
            ),
        createHttpClient: (_) =>
            throw StateError('Network is forbidden in ZIP tests.'));
  }
}

Future<Map<String, String>> fictionalSnapshot(Directory root) async {
  final result = <String, String>{};
  if (!await root.exists()) return result;
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    if (entry is! File) continue;
    final relative =
        p.relative(entry.path, from: root.path).replaceAll('\\', '/');
    if (relative == '.operation.lock') continue;
    result[relative] = await legacyZipHash(await entry.readAsBytes());
  }
  return result;
}

final class SyntheticPickedFile extends PlatformFile {
  SyntheticPickedFile(this.chunks);
  final Stream<Uint8List> Function() chunks;
  @override
  String get name => 'fictional.zip';
  @override
  Uri get uri => Uri.parse('content://synthetic/fictional.zip');
  @override
  XFile get xFile => throw StateError('XFile is not used by this test.');
  @override
  int? lengthSync() => null;
  @override
  Future<int?> length() async => null;
  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('Unbounded reads are forbidden.');
  @override
  Stream<Uint8List> readAsByteStream() => chunks();
}
