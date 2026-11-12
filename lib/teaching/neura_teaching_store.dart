import '../core/memory/memory_crypto.dart';
import '../startup/neura_prefs_cache.dart';
import 'neura_teaching_preferences.dart';

abstract interface class NeuraTeachingStore {
  Future<NeuraTeachingPreferences> read(
      {required bool Function() stillAllowed});

  /// A loaded cache must not outlive the encryption authority that admitted it.
  bool get authorityCurrent;

  /// Recheck permission immediately before submitting the platform mutation.
  /// Once submitted, an OS write cannot be cancelled; the owner must drain it.
  Future<void> write(NeuraTeachingPreferences value,
      {required bool Function() stillAllowed});
}

class NeuraEncryptedTeachingStore implements NeuraTeachingStore {
  static const storageKey = 'neura.teaching.explicit_preferences.v1';
  MemoryCrypto? _authority;
  bool _hasRecord = false;

  @override
  bool get authorityCurrent {
    if (!_hasRecord) return true;
    try {
      final authority = _authority;
      if (authority == null) return false;
      authority.requireOsBackedKey();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<NeuraTeachingPreferences> read(
      {required bool Function() stillAllowed}) async {
    void check() {
      if (!stillAllowed()) throw StateError('Teaching load was cancelled.');
    }

    check();
    final prefs = NeuraPrefsCache.prefs;
    await prefs.reload();
    check();
    final raw = prefs.getString(storageKey);
    _hasRecord = raw != null;
    _authority = null;
    if (raw == null) return const NeuraTeachingPreferences();
    if (raw.isEmpty || raw.length > 4096) {
      throw const FormatException('Invalid teaching settings envelope.');
    }
    final crypto = await MemoryCrypto.demo();
    check();
    crypto.requireOsBackedKey();
    final value = await crypto.decryptJson(raw);
    check();
    crypto.requireOsBackedKey();
    final decoded = NeuraTeachingPreferences.fromJson(value);
    _authority = crypto;
    return decoded;
  }

  @override
  Future<void> write(NeuraTeachingPreferences value,
      {required bool Function() stillAllowed}) async {
    final prefs = NeuraPrefsCache.prefs;
    if (value.isEmpty) {
      if (!stillAllowed()) throw StateError('Teaching change was cancelled.');
      if (!await prefs.remove(storageKey)) {
        throw StateError('Teaching removal could not be confirmed.');
      }
      await prefs.reload();
      if (prefs.containsKey(storageKey)) {
        throw StateError('Teaching removal could not be verified.');
      }
      _hasRecord = false;
      _authority = null;
      return;
    }
    if (!stillAllowed()) throw StateError('Teaching change was cancelled.');
    final crypto = await MemoryCrypto.demo();
    crypto.requireOsBackedKey();
    final ciphertext = await crypto.encryptJson(value.toJson());
    crypto.requireOsBackedKey();
    if (!stillAllowed()) throw StateError('Teaching change was cancelled.');
    if (!await prefs.setString(storageKey, ciphertext)) {
      throw StateError('Teaching save could not be confirmed.');
    }
    await prefs.reload();
    if (prefs.getString(storageKey) != ciphertext) {
      throw StateError('Teaching save could not be verified.');
    }
    _authority = crypto;
    _hasRecord = true;
  }
}
