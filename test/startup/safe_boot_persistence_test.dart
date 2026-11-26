import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:neuro_companion/reliability/safe_boot.dart';

class _SyntheticSupport extends PathProviderPlatform {
  _SyntheticSupport(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed mode save does not promise a normal next launch', () async {
    final originalProvider = PathProviderPlatform.instance;
    final support = await Directory.systemTemp.createTemp('neura-mode-test-');
    final boot = SafeBoot.instance;
    try {
      PathProviderPlatform.instance = _SyntheticSupport(support.path);
      await boot.beginBoot();
      await boot.requestSafeMode();
      final state = File('${support.path}/neura/health/boot-state.json');
      await state.delete();
      await Directory(state.path).create();

      await expectLater(
          boot.clearSafeMode(), throwsA(isA<FileSystemException>()));
      expect(boot.safeMode.value, isTrue);
      expect(boot.restartRequired.value, isFalse);
      expect(boot.consecutiveFailures, 2);

      await Directory(state.path).delete();
      await boot.clearSafeMode();
      expect(boot.safeMode.value, isTrue);
      expect(boot.restartRequired.value, isTrue);
      expect(boot.consecutiveFailures, 0);
    } finally {
      PathProviderPlatform.instance = originalProvider;
      await support.delete(recursive: true);
    }
  });
}
