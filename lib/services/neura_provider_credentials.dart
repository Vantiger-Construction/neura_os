import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal credential-store boundary used to make migration and deletion
/// behavior testable without ever exposing a real provider key.
abstract interface class NeuraCredentialStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class _NeuraSecureCredentialStorage implements NeuraCredentialStorage {
  const _NeuraSecureCredentialStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Owns Neura's model-provider credential.
///
/// The key is cached in memory for synchronous request construction and stored
/// by the operating system's secure credential facility. A legacy build-time
/// key is migrated once so existing installations keep working; future builds
/// should omit `--dart-define=ANTHROPIC_API_KEY=...` entirely.
class NeuraProviderCredentials {
  NeuraProviderCredentials._({
    NeuraCredentialStorage? storage,
    String? legacyBuildKey,
  })  : _storage = storage ?? const _NeuraSecureCredentialStorage(),
        _legacyBuildKey = legacyBuildKey ?? _legacyBuildKeyFromEnvironment;

  static final NeuraProviderCredentials instance = NeuraProviderCredentials._();

  /// Creates an isolated credential owner for deterministic storage tests.
  /// Production code must use [instance].
  @visibleForTesting
  factory NeuraProviderCredentials.forTesting({
    required NeuraCredentialStorage storage,
    String legacyBuildKey = '',
  }) {
    return NeuraProviderCredentials._(
      storage: storage,
      legacyBuildKey: legacyBuildKey,
    );
  }

  static const _storageKey = 'neura.anthropic_api_key.v1';
  static const _legacyMigrationTombstoneKey =
      'neura.anthropic_api_key.legacy_migration_disabled.v1';
  static const _legacyBuildKeyFromEnvironment =
      String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');
  static const _tombstoneValue = 'disabled';

  final NeuraCredentialStorage _storage;
  final String _legacyBuildKey;
  final ValueNotifier<bool> configured = ValueNotifier(false);

  String _apiKey = '';
  bool _initialized = false;
  bool _writesSuspended = false;
  bool _clearInProgress = false;
  Future<void> _operationQueue = Future<void>.value();

  bool get isInitialized => _initialized;
  bool get hasKey => _apiKey.isNotEmpty;

  /// Returns the in-memory key. It is intentionally never exposed by the UI.
  String get apiKey => _apiKey;

  Future<void> initialize() {
    if (_writesSuspended || _clearInProgress) {
      return Future<void>.error(
        StateError('Provider credential access is suspended.'),
      );
    }
    return _enqueueMutation(() async {
      if (_initialized) return;
      if (_writesSuspended || _clearInProgress) {
        throw StateError('Provider credential access is suspended.');
      }

      var stored = (await _storage.read(key: _storageKey) ?? '').trim();
      final migrationDisabled = await _migrationIsDisabled();
      final legacyCandidate = _legacyBuildKey.trim();

      if (!migrationDisabled && legacyCandidate.isNotEmpty) {
        if (stored.isEmpty) {
          await _storage.write(key: _storageKey, value: legacyCandidate);
          stored = (await _storage.read(key: _storageKey) ?? '').trim();
          if (stored != legacyCandidate) {
            throw StateError(
              'The migrated provider credential could not be verified in secure storage.',
            );
          }
          debugPrint(
            '[NeuraCredentials] Migrated a legacy build credential to secure '
            'storage. Rebuild without ANTHROPIC_API_KEY to remove it from the binary.',
          );
        }

        // A successful migration (or an already-present secure credential)
        // permanently disables fallback to the key baked into this binary.
        // Without this tombstone, clearing secure storage would resurrect the
        // supposedly deleted build-time credential on the next launch.
        await _writeAndVerifyMigrationTombstone();
      }

      _apiKey = stored;
      _initialized = true;
      configured.value = hasKey;
    });
  }

  Future<void> save(String value) {
    if (_writesSuspended || _clearInProgress) {
      return Future<void>.error(
        StateError('Provider credential changes are suspended.'),
      );
    }
    return _enqueueMutation(() async {
      if (_writesSuspended || _clearInProgress) {
        throw StateError('Provider credential changes are suspended.');
      }
      final candidate = value.trim();
      final validation = validate(candidate);
      if (validation != null) throw FormatException(validation);

      await _storage.write(key: _storageKey, value: candidate);
      final stored = (await _storage.read(key: _storageKey) ?? '').trim();
      if (stored != candidate) {
        throw StateError(
          'The provider credential could not be verified in secure storage.',
        );
      }
      await _writeAndVerifyMigrationTombstone();
      _apiKey = candidate;
      _initialized = true;
      configured.value = true;
    });
  }

  /// Removes the secure credential and permanently disables legacy fallback.
  ///
  /// Both operations are attempted even if the first one fails. The in-memory
  /// copy is cleared as soon as secure deletion is verified, but the returned
  /// future fails unless *both* the deletion and tombstone can be verified.
  Future<void> clear() async {
    if (_writesSuspended) {
      throw StateError('Provider credential changes are suspended.');
    }
    _clearInProgress = true;
    try {
      await _enqueueMutation(_clearNow);
    } finally {
      _clearInProgress = false;
    }
  }

  /// Stops future credential writes for this process, drains any mutation
  /// already queued, then performs the same verified deletion as [clear].
  /// A restart is the only resume boundary after a full local-data wipe.
  Future<void> clearForDataWipe() {
    _writesSuspended = true;
    return _enqueueMutation(_clearNow);
  }

  Future<void> _clearNow() async {
    var tombstoneVerified = false;
    var deletionVerified = false;

    try {
      await _writeAndVerifyMigrationTombstone();
      tombstoneVerified = true;
    } catch (_) {
      // Still attempt secret deletion. The caller receives a visible failure
      // below so a missing tombstone can never be reported as a complete wipe.
    }

    try {
      await _storage.delete(key: _storageKey);
      final remaining = (await _storage.read(key: _storageKey) ?? '').trim();
      deletionVerified = remaining.isEmpty;
    } catch (_) {
      deletionVerified = false;
    }

    if (deletionVerified) {
      _apiKey = '';
      _initialized = true;
      configured.value = false;
    }

    if (!deletionVerified || !tombstoneVerified) {
      final problem = !deletionVerified && !tombstoneVerified
          ? 'secure deletion and legacy-migration blocking'
          : !deletionVerified
              ? 'secure deletion'
              : 'legacy-migration blocking';
      throw StateError(
        'Provider credential removal is incomplete: $problem could not be verified.',
      );
    }
  }

  Future<void> _enqueueMutation(Future<void> Function() operation) {
    final next = _operationQueue.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _operationQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<bool> _migrationIsDisabled() async {
    final value = await _storage.read(key: _legacyMigrationTombstoneKey);
    return value == _tombstoneValue;
  }

  Future<void> _writeAndVerifyMigrationTombstone() async {
    await _storage.write(
      key: _legacyMigrationTombstoneKey,
      value: _tombstoneValue,
    );
    if (!await _migrationIsDisabled()) {
      throw StateError(
        'Legacy provider-credential migration could not be disabled.',
      );
    }
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
