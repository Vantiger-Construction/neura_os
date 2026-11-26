import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' hide Sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/src/modules/legacy/legacy_vault_zip_codec.dart';
import 'package:neuro_companion/src/modules/legacy/models/legacy_capsule.dart';

import 'legacy_zip_fixture.dart';

void main() {
  for (final producer in ['4.6.0', '4.7.1']) {
    for (final mode in ['raw', 'clear', 'wrong']) {
      test(
          'restores frozen archive $producer $mode with exact capsule and attachment data',
          () async {
        final fixture = await LegacyZipFixture.create();
        final zip = await fixture.archive(producer, 'vault_$mode');
        final service = fixture.service();
        await fixture.run(() async {
          final source = ZipDecoder().decodeBytes(await zip.readAsBytes(),
              verify: true, throwOnError: true);
          final result = await service.importVaultZipResult(zip);
          expect(result.imported, 2);
          expect(result.skipped, 0);
          expect(result.cleanupPending, isFalse);
          for (final record
              in source.files.where((f) => f.name.startsWith('capsules/'))) {
            final original =
                LegacyCapsule.fromJson(utf8.decode(record.content));
            final restored = (await service.loadCapsule(original.id))!;
            expect(restored.toMap(), original.toMap());
            if (restored.isEncrypted) {
              expect(
                  await service.decryptBody(
                      capsule: restored, passphrase: fictionalPassphrase),
                  fictionalSecret);
            }
            for (final relative in restored.attachments) {
              final originalBytes = source.files
                  .firstWhere((f) =>
                      f.name ==
                      'attachments/${restored.id}/${relative.split('/').last}')
                  .content;
              expect(
                  await legacyZipHash(
                      await (await service.resolveAttachmentFile(relative))
                          .readAsBytes()),
                  await legacyZipHash(originalBytes));
            }
          }
          final before = await fictionalSnapshot(fixture.vault);
          final duplicate = await service.importVaultZipResult(zip);
          expect(duplicate.imported, 0);
          expect(duplicate.skipped, 2);
          expect(await fictionalSnapshot(fixture.vault), before);
        });
      });
    }
    for (final name in ['comment_eocd', 'long_trailing']) {
      test('restores $producer $name without false empty success', () async {
        final f = await LegacyZipFixture.create();
        final zip = await f.archive(producer, name);
        await f.run(() async {
          expect(await f.service().importVaultZip(zip), 2);
        });
      });
    }
  }

  test('existing ID skips its entire attachment unit', () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    final service = f.service();
    await f.run(() async {
      final dir = await service.capsuleAttachmentDir('fic_plain');
      await File('${dir.path}/local.txt')
          .writeAsString('Fictional existing local attachment.');
      await service.saveCapsule(fictionalCapsule('fic_plain',
          attachments: ['capsule_fic_plain/attachments/local.txt']));
      final oldJson =
          await File('${f.vault.path}/capsule_fic_plain.json').readAsBytes();
      final oldAttachment = await File('${dir.path}/local.txt').readAsBytes();
      final result = await service.importVaultZipResult(zip);
      expect(result.imported, 1);
      expect(result.skipped, 1);
      expect(await File('${f.vault.path}/capsule_fic_plain.json').readAsBytes(),
          oldJson);
      expect(await File('${dir.path}/local.txt').readAsBytes(), oldAttachment);
      expect((await dir.list().toList()).length, 1);
    });
  });

  test(
      'new exports verify their manifest and clear crypto fields only after decryption',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.7.1', 'vault_raw');
    final service = f.service();
    await f.run(() async {
      await service.importVaultZip(zip);
      final raw = await service.exportVaultZipResult();
      final rawPlan =
          await const LegacyVaultZipCodec().plan(await raw.file.readAsBytes());
      expect(rawPlan.capsules.length, 2);
      expect(raw.encryptedCapsules, 1);
      final fallback = await service.exportVaultZipResult(
          decryptEncrypted: true, passphrase: 'WRONG fictional phrase');
      expect(fallback.encryptedCapsules, 1);
      expect(fallback.description, contains('remain encrypted'));
      final clear = await service.exportVaultZipResult(
          decryptEncrypted: true, passphrase: fictionalPassphrase);
      final clearPlan = await const LegacyVaultZipCodec()
          .plan(await clear.file.readAsBytes());
      final secret = clearPlan.capsules.firstWhere((c) => c.id == 'fic_secret');
      expect(secret.body, fictionalSecret);
      expect(secret.isEncrypted, isFalse);
      expect([
        secret.cipherTextB64,
        secret.nonceB64,
        secret.macB64,
        secret.saltB64
      ], everyElement(isNull));
      final packet = await service.exportCapsuleZip('fic_secret',
          decrypted: true, passphrase: fictionalPassphrase);
      final decoded =
          const LegacyVaultZipCodec().decode(await packet.readAsBytes());
      final body = LegacyCapsule.fromJson(utf8.decode(
          decoded.files.firstWhere((f) => f.name == 'capsule.json').content));
      expect(body.body, fictionalSecret);
      expect(body.cipherTextB64, isNull);
      final json = await service.exportCapsule('fic_secret',
          decrypted: true, passphrase: fictionalPassphrase);
      expect(LegacyCapsule.fromJson(await json.readAsString()).cipherTextB64,
          isNull);
      expect(
          () => service.decryptBody(
              capsule: rawPlan.capsules.firstWhere((c) => c.id == 'fic_secret'),
              passphrase: 'WRONG fictional phrase'),
          throwsA(anything));
    });
  });

  test('delivery packets preserve encryption state and every attachment',
      () async {
    final f = await LegacyZipFixture.create();
    final zip = await f.archive('4.6.0', 'vault_raw');
    await f.run(() async {
      final service = f.service();
      await service.importVaultZip(zip);
      final original = (await service.loadCapsule('fic_secret'))!;
      for (final mode in ['raw', 'clear', 'wrong']) {
        final packet = await service.exportCapsuleZip('fic_secret',
            decrypted: mode != 'raw',
            passphrase: mode == 'wrong' ? 'WRONG phrase' : fictionalPassphrase);
        final decoded =
            const LegacyVaultZipCodec().decode(await packet.readAsBytes());
        final contents = {
          for (final file in decoded.files) file.name: file.content
        };
        final capsule =
            LegacyCapsule.fromJson(utf8.decode(contents['capsule.json']!));
        final readme = utf8.decode(contents['README.txt']!);
        expect(capsule.isEncrypted, mode != 'clear');
        if (mode != 'clear') {
          expect(capsule.toMap(), original.toMap());
          expect(readme, contains('body remains encrypted'));
        } else {
          expect(capsule.body, fictionalSecret);
          expect(capsule.cipherTextB64, isNull);
          expect(readme, contains('body is plaintext'));
        }
        for (final path in original.attachments) {
          final bytes =
              await (await service.resolveAttachmentFile(path)).readAsBytes();
          expect(
              await legacyZipHash(
                  contents['attachments/${path.split('/').last}']!),
              await legacyZipHash(bytes));
        }
      }
    });
  });
}
