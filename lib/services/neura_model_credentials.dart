import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'neura_model_types.dart';

abstract interface class NeuraModelCredentialStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class NeuraSecureModelCredentialStorage implements NeuraModelCredentialStorage {
  const NeuraSecureModelCredentialStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Stores model credentials separately in the operating-system credential
/// store. Secret values are never exposed through notifiers, logs, or previews.
class NeuraModelCredentials {
  NeuraModelCredentials._({NeuraModelCredentialStorage? storage})
      : _storage = storage ?? const NeuraSecureModelCredentialStorage();

  static final NeuraModelCredentials instance = NeuraModelCredentials._();

  @visibleForTesting
  factory NeuraModelCredentials.forTesting(
    NeuraModelCredentialStorage storage,
  ) {
    return NeuraModelCredentials._(storage: storage);
  }

  final NeuraModelCredentialStorage _storage;
  final ValueNotifier<Set<NeuraModelProvider>> configured = ValueNotifier(
    <NeuraModelProvider>{},
  );
  Future<void> _queue = Future<void>.value();
  bool _writesSuspended = false;

  static const _keys = {
    NeuraModelProvider.openAi: 'neura.openai_api_key.v1',
    NeuraModelProvider.anthropic: 'neura.anthropic_api_key.v1',
  };

  Future<void> initialize() {
    return _enqueue(() async {
      _requireReadable();
      final available = <NeuraModelProvider>{};
      for (final provider in NeuraModelProvider.values) {
        final value = (await _storage.read(key: _keys[provider]!) ?? '').trim();
        if (value.isNotEmpty) available.add(provider);
      }
      _requireReadable();
      configured.value = Set.unmodifiable(available);
    });
  }

  Future<String?> read(NeuraModelProvider provider) async {
    _requireReadable();
    final value = (await _storage.read(key: _keys[provider]!) ?? '').trim();
    // Recheck after the platform await: an already-started read may return
    // stale bytes after a concurrent wipe revoked credential access.
    _requireReadable();
    return value.isEmpty ? null : value;
  }

  void _requireReadable() {
    if (_writesSuspended) {
      throw StateError('Model credential access is suspended.');
    }
  }

  Future<void> save(NeuraModelProvider provider, String value) {
    return _enqueue(() async {
      if (_writesSuspended) {
        throw StateError('Model credential changes are suspended.');
      }
      final candidate = value.trim();
      final error = validate(provider, candidate);
      if (error != null) throw FormatException(error);
      final key = _keys[provider]!;
      await _storage.write(key: key, value: candidate);
      if ((await _storage.read(key: key) ?? '').trim() != candidate) {
        throw StateError('The model credential could not be verified.');
      }
      configured.value = Set.unmodifiable({...configured.value, provider});
    });
  }

  Future<void> clear(NeuraModelProvider provider) {
    return _enqueue(() async {
      if (_writesSuspended) {
        throw StateError('Model credential changes are suspended.');
      }
      await _deleteAndVerify(provider);
    });
  }

  Future<void> clearForDataWipe() {
    _writesSuspended = true;
    configured.value = const <NeuraModelProvider>{};
    return _enqueue(() async {
      try {
        final failures = <NeuraModelProvider>[];
        for (final provider in NeuraModelProvider.values) {
          try {
            await _deleteAndVerify(provider);
          } catch (_) {
            failures.add(provider);
          }
        }
        if (failures.isNotEmpty) {
          throw StateError('Model credential deletion could not be verified.');
        }
      } finally {
        configured.value = const <NeuraModelProvider>{};
      }
    });
  }

  Future<void> _deleteAndVerify(NeuraModelProvider provider) async {
    final key = _keys[provider]!;
    await _storage.delete(key: key);
    if ((await _storage.read(key: key) ?? '').trim().isNotEmpty) {
      throw StateError('Model credential deletion could not be verified.');
    }
    configured.value = Set.unmodifiable(
      configured.value.where((item) => item != provider),
    );
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _queue.then((_) => operation(), onError: (_) => operation());
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static String? validate(NeuraModelProvider provider, String value) {
    final candidate = value.trim();
    if (candidate.isEmpty) return 'Enter a ${provider.label} API key.';
    final validPrefix = switch (provider) {
      NeuraModelProvider.openAi => candidate.startsWith('sk-'),
      NeuraModelProvider.anthropic => candidate.startsWith('sk-ant-'),
    };
    if (!validPrefix) {
      return 'This does not look like a ${provider.label} API key.';
    }
    if (candidate.length < 24) return 'The API key appears incomplete.';
    if (candidate.contains(RegExp(r'\s'))) {
      return 'The API key cannot contain spaces.';
    }
    return null;
  }
}
