import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';

import 'helpers/mock_path_provider.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('neura-wipe-test-');
    registerMockPathProvider(rootPath: root.path);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('Legacy Vault wipe deletes only its exact app-owned directory',
      () async {
    final vault = Directory(
      '${root.path}${Platform.pathSeparator}neura_legacy_vault',
    );
    final neighbor = Directory(
      '${root.path}${Platform.pathSeparator}neura_legacy_vault_backup',
    );
    await vault.create(recursive: true);
    await neighbor.create(recursive: true);
    await File('${vault.path}${Platform.pathSeparator}capsule_private.json')
        .writeAsString('private');
    final neighborFile =
        File('${neighbor.path}${Platform.pathSeparator}keep.txt');
    await neighborFile.writeAsString('unrelated');

    await NeuraDataWipeService.wipeLegacyVault();

    expect(await vault.exists(), isFalse);
    expect(await neighbor.exists(), isTrue);
    expect(await neighborFile.readAsString(), 'unrelated');
  });
}
