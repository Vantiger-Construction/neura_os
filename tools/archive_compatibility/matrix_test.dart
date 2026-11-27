import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/src/modules/legacy/legacy_vault_zip_codec.dart';

import '../../test/legacy/legacy_zip_fixture.dart';

const outputPath = String.fromEnvironment('NEURA_ZIP_MATRIX_OUTPUT');
const inputPath = String.fromEnvironment('NEURA_ZIP_MATRIX_INPUT');
const producer = String.fromEnvironment('NEURA_ZIP_MATRIX_PRODUCER');
const reader = String.fromEnvironment('NEURA_ZIP_MATRIX_READER');

Future<Directory> matrixRoot(String path) async {
  if (path.isEmpty ||
      await File('$path/SYNTHETIC_ONLY').readAsString() !=
          'FICTIONAL ZIP MATRIX ONLY') {
    throw StateError('A dedicated fictional matrix directory is required.');
  }
  return Directory(path);
}

void main() {
  if (inputPath.isEmpty) {
    test(
        'produce fresh raw, decrypted and fallback exports with archive $producer',
        () async {
      final output = await matrixRoot(outputPath);
      final f = await LegacyZipFixture.create();
      final source = await f.archive('4.6.0', 'vault_raw');
      final exports = <String, List<int>>{};
      await f.run(() async {
        final service = f.service();
        await service.importVaultZip(source);
        for (final mode in ['raw', 'clear', 'wrong']) {
          final result = await service.exportVaultZipResult(
              decryptEncrypted: mode != 'raw',
              passphrase: mode == 'wrong'
                  ? 'WRONG fictional phrase'
                  : fictionalPassphrase);
          exports[mode] = await result.file.readAsBytes();
        }
      });
      final manifest = <String, dynamic>{};
      for (final export in exports.entries) {
        await File('${output.path}/vault_${export.key}.zip')
            .writeAsBytes(export.value, flush: true);
        manifest[export.key] = {
          'sha256': await legacyZipHash(export.value),
          'bytes': export.value.length
        };
      }
      await File('${output.path}/producer.json').writeAsString(jsonEncode(
          {'archive': producer, 'syntheticOnly': true, 'exports': manifest}));
    });
  } else {
    test('import fresh archive $producer exports with archive $reader',
        () async {
      final input = await matrixRoot(inputPath);
      final output = await matrixRoot(outputPath);
      final results = <Map<String, dynamic>>[];
      for (final mode in ['raw', 'clear', 'wrong']) {
        final f = await LegacyZipFixture.create();
        final bytes = await File('${input.path}/vault_$mode.zip').readAsBytes();
        final zip = await f.zip(bytes);
        await f.run(() async {
          final service = f.service();
          final expected = await const LegacyVaultZipCodec().plan(bytes);
          final imported = await service.importVaultZipResult(zip);
          expect(imported.imported, 2);
          expect(imported.cleanupPending, isFalse);
          var attachments = 0;
          for (final capsule in expected.capsules) {
            final restored = (await service.loadCapsule(capsule.id))!;
            expect(restored.toMap(), capsule.toMap());
            if (restored.id == 'fic_secret') {
              expect(
                  await service.decryptBody(
                      capsule: restored, passphrase: fictionalPassphrase),
                  fictionalSecret);
              if (mode == 'clear') expect(restored.cipherTextB64, isNull);
            }
            for (final path in restored.attachments) {
              final normalized = path.replaceAll('\\', '/');
              expect(
                  await legacyZipHash(
                      await (await service.resolveAttachmentFile(path))
                          .readAsBytes()),
                  await legacyZipHash(expected.files[normalized]!));
              attachments++;
            }
          }
          expect(attachments, 4);
          results.add({
            'mode': mode,
            'imported': imported.imported,
            'exactCapsuleData': true,
            'encryptedBodyAuthenticatedOrPlaintextMatched': true,
            'attachmentHashesMatched': attachments,
            'passed': true
          });
        });
      }
      await File('${output.path}/consumer.json').writeAsString(jsonEncode({
        'producer': producer,
        'reader': reader,
        'syntheticOnly': true,
        'results': results
      }));
    });
  }
}
