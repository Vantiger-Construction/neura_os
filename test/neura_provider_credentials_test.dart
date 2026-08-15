import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_provider_credentials.dart';

void main() {
  group('NeuraProviderCredentials.validate', () {
    test('rejects blank values', () {
      expect(NeuraProviderCredentials.validate('  '), isNotNull);
    });

    test('rejects keys for another provider', () {
      expect(
        NeuraProviderCredentials.validate('sk-proj-not-an-anthropic-key'),
        isNotNull,
      );
    });

    test('rejects whitespace inside a key', () {
      expect(
        NeuraProviderCredentials.validate(
          'sk-ant-api03-this key contains whitespace',
        ),
        isNotNull,
      );
    });

    test('accepts a structurally plausible Anthropic key', () {
      expect(
        NeuraProviderCredentials.validate(
          'sk-ant-' 'api03-example-value-long-enough-for-local-validation',
        ),
        isNull,
      );
    });
  });

  group('legacy credential migration', () {
    const legacyKey = 'sk-ant-'
        'api03-legacy-value-long-enough-for-local-validation';

    test('clear tombstones the build key so it cannot resurrect', () async {
      final storage = _MemoryCredentialStorage();
      final firstRun = NeuraProviderCredentials.forTesting(
        storage: storage,
        legacyBuildKey: legacyKey,
      );

      await firstRun.initialize();
      expect(firstRun.hasKey, isTrue);

      await firstRun.clear();
      expect(firstRun.hasKey, isFalse);

      final restarted = NeuraProviderCredentials.forTesting(
        storage: storage,
        legacyBuildKey: legacyKey,
      );
      await restarted.initialize();

      expect(restarted.hasKey, isFalse);
      expect(restarted.apiKey, isEmpty);
    });

    test('clear fails visibly when secure deletion cannot be verified',
        () async {
      final storage = _MemoryCredentialStorage(ignoreDeletes: true);
      final credentials = NeuraProviderCredentials.forTesting(
        storage: storage,
        legacyBuildKey: legacyKey,
      );
      await credentials.initialize();

      await expectLater(credentials.clear(), throwsStateError);
      expect(credentials.hasKey, isTrue);
      expect(credentials.configured.value, isTrue);
    });

    test('explicit save also disables future legacy fallback', () async {
      final storage = _MemoryCredentialStorage();
      final credentials = NeuraProviderCredentials.forTesting(
        storage: storage,
        legacyBuildKey: legacyKey,
      );
      const replacement = 'sk-ant-'
          'api03-replacement-value-long-enough-for-validation';

      await credentials.save(replacement);
      await credentials.clear();

      final restarted = NeuraProviderCredentials.forTesting(
        storage: storage,
        legacyBuildKey: legacyKey,
      );
      await restarted.initialize();
      expect(restarted.hasKey, isFalse);
    });

    test('data-wipe clear blocks later writes for this process', () async {
      final storage = _MemoryCredentialStorage();
      final credentials = NeuraProviderCredentials.forTesting(
        storage: storage,
        legacyBuildKey: legacyKey,
      );
      await credentials.initialize();

      await credentials.clearForDataWipe();

      await expectLater(credentials.save(legacyKey), throwsStateError);
      expect(credentials.hasKey, isFalse);
    });
  });
}

class _MemoryCredentialStorage implements NeuraCredentialStorage {
  _MemoryCredentialStorage({this.ignoreDeletes = false});

  final bool ignoreDeletes;
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    if (!ignoreDeletes) values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
