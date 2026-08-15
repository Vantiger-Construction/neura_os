import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owns Neura's model-provider credential.
///
/// The key is cached in memory for synchronous request construction and stored
/// by the operating system's secure credential facility. A legacy build-time
/// key is migrated once so existing installations keep working; future builds
/// should omit `--dart-define=ANTHROPIC_API_KEY=...` entirely.
class NeuraProviderCredentials {
  NeuraProviderCredentials._();
  static final NeuraProviderCredentials instance =
      NeuraProviderCredentials._();

  static const _storageKey = 'neura.anthropic_api_key.v1';
  static const _legacyBuildKey =
      String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ValueNotifier<bool> configured = ValueNotifier(false);

  String _apiKey = '';
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool get hasKey => _apiKey.isNotEmpty;

  /// Returns the in-memory key. It is intentionally never exposed by the UI.
  String get apiKey => _apiKey;

  Future<void> initialize() async {
    if (_initialized) return;

    var stored = (await _storage.read(key: _storageKey) ?? '').trim();
    if (stored.isEmpty && _legacyBuildKey.trim().isNotEmpty) {
      stored = _legacyBuildKey.trim();
      await _storage.write(key: _storageKey, value: stored);
      debugPrint(
        '[NeuraCredentials] Migrated legacy build credential to secure storage. '
        'Rebuild without ANTHROPIC_API_KEY to remove it from the binary.',
      );
    }

    _apiKey = stored;
    _initialized = true;
    configured.value = hasKey;
  }

  Future<void> save(String value) async {
    final candidate = value.trim();
    final validation = validate(candidate);
    if (validation != null) throw FormatException(validation);

    await _storage.write(key: _storageKey, value: candidate);
    _apiKey = candidate;
    _initialized = true;
    configured.value = true;
  }

  Future<void> clear() async {
    await _storage.delete(key: _storageKey);
    _apiKey = '';
    _initialized = true;
    configured.value = false;
  }

  /// Performs deliberately conservative local validation without contacting
  /// the provider or recording any portion of the secret.
  static String? validate(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty) return 'Enter an Anthropic API key.';
    if (!candidate.startsWith('sk-ant-')) {
      return 'This does not look like an Anthropic API key.';
    }
    if (candidate.length < 24) return 'The API key appears incomplete.';
    if (candidate.contains(RegExp(r'\s'))) {
      return 'The API key cannot contain spaces.';
    }
    return null;
  }
}
