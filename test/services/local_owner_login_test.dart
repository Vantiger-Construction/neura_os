import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/local_owner_login.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const password = 'synthetic owner passphrase';
  late Map<String, String> disk;
  setUp(() {
    disk = {};
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return disk[key];
        case 'write':
          disk[key] = args['value'] as String;
          return null;
        case 'delete':
          disk.remove(key);
          return null;
      }
      throw UnsupportedError(call.method);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('relaunch preserves opt-in, verifies the device and supports revocation',
      () async {
    final first = LocalOwnerLogin();
    expect(await first.remembered(), isNull);
    await first.create(password, remember: true);
    expect(disk.values.single, isNot(contains(password)));
    final next = LocalOwnerLogin();
    expect(await next.remembered(), isTrue);
    await expectLater(next.create('second synthetic phrase', remember: false),
        throwsStateError);
    expect(await next.unlockRemembered(() async => false), isFalse);
    expect(await next.unlockRemembered(() async => true), isTrue);
    expect(await next.unlock('wrong fixture', remember: false), isFalse);
    expect(await next.remembered(), isTrue);
    expect(await next.unlock(password, remember: false), isTrue);
    expect(
        await next.unlockRemembered(() => throw StateError('must not prompt')),
        isFalse);
    expect(await next.remove('wrong fixture'), isFalse);
    expect(await next.remove(password), isTrue);
    expect(await next.remembered(), isNull);
  });

  test('malformed records fail closed and a full wipe revokes pending access',
      () async {
    final login = LocalOwnerLogin();
    disk[LocalOwnerLogin.storageKey] = 'broken synthetic record';
    await expectLater(login.remembered(), throwsFormatException);
    final read = expectLater(login.remembered(), throwsStateError);
    await login.clearForDataWipe();
    await read;
    expect(disk, isEmpty);
    await expectLater(login.create(password, remember: true), throwsStateError);
  });
}
