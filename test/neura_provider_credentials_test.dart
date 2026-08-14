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
}
