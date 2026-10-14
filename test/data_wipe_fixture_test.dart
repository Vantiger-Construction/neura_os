import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fixture accepts equivalent native and slash paths', () async {
    final f = await DataWipeFixture.create();
    await f.run(() async {
      final file = await f.seed('${f.documents.path}/nested/private.txt');
      final nativePath = file.path.replaceAll('/', Platform.pathSeparator);
      expect(
          await File(nativePath).readAsString(), 'synthetic private fixture');
      expect(
          await File('${f.documents.path}/nested/../nested/private.txt')
              .exists(),
          isTrue);
    });
    f.expectIsolation();
  });

  test('fixture rejects traversal and similarly prefixed sibling paths',
      () async {
    final f = await DataWipeFixture.create();
    final paths = [
      '${f.root.path}/../outside.txt',
      '${f.root.path}-neighbor/private.txt',
      '${f.documents.path}/../../outside.txt',
    ];
    await f.run(() async {
      for (final path in paths) {
        expect(() => File(path), throwsStateError);
        expect(() => Directory(path), throwsStateError);
        expect(() => Link(path), throwsStateError);
        await expectLater(FileSystemEntity.type(path), throwsStateError);
      }
    });
    expect(f.escapedPaths.length, paths.length * 4);
    expect(f.platformCalls, isEmpty);
    expect(f.networkAttempts, 0);
  });

  test('fixture matches paused and blocked files across separator spellings',
      () async {
    final f = await DataWipeFixture.create();
    final file = await f.seed('${f.documents.path}/nested/private.txt');
    final nativePath = file.path.replaceAll('/', Platform.pathSeparator);
    final paused = PausedWipeFile(file);
    f.pausedFile = paused;
    f.blockedPaths.add(file.path);
    await f.run(() async {
      expect(identical(File(nativePath), paused), isTrue);
      await expectLater(FileSystemEntity.type(nativePath),
          throwsA(isA<FileSystemException>()));
    });
    f.expectIsolation();
  });
}
