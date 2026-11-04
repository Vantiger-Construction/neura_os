import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android reads migrate legacy keys with backup and never reset on error',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'read');
      final options = (call.arguments as Map)['options'] as Map;
      expect(options['resetOnError'], 'false');
      expect(options['migrateOnAlgorithmChange'], 'true');
      expect(options['migrateWithBackup'], 'true');
      return 'existing-encryption-key';
    });

    expect(await neuraSecureStorage.read(key: 'memory-key'),
        'existing-encryption-key');
  });

  test('unavailable key storage surfaces the failure without deleting keys',
      () async {
    final operations = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      operations.add(call.method);
      throw PlatformException(code: 'StorageError');
    });

    await expectLater(neuraSecureStorage.read(key: 'memory-key'),
        throwsA(isA<PlatformException>()));
    expect(operations, ['read']);
  });
}
