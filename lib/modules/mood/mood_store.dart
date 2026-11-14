import 'dart:async';
import 'dart:convert';

import 'mood_models.dart';
import '../../core/memory/memory_crypto.dart';
import '../../os_shell/widgets_bridge/home_widget_bridge.dart';
import '../../startup/neura_prefs_cache.dart';

/// The platform did not confirm this write. Restart before reading or retrying
/// so speculative preferences cache contents cannot be treated as saved data.
class MoodSaveUnconfirmedException implements Exception {
  const MoodSaveUnconfirmedException();

  @override
  String toString() => 'Mood history save could not be confirmed.';
}

/// Local mood history, encrypted at rest (reuses the same per-install key
/// as [MemoryCrypto]'s other callers). Previously stored as a plain JSON
/// string via SharedPreferences - mood entries are as sensitive as
/// anything else on-device, so this brings them in line with the memory
/// graph and therapy journal.
class MoodStore {
  MoodStore._();
  static final MoodStore instance = MoodStore._();

  static const _key = 'neura_mood_entries_v1';

  MemoryCrypto? _crypto;
  Future<void> _writeQueue = Future<void>.value();
  bool _writesSuspended = false;
  bool _storageUnconfirmed = false;
  int _dataGeneration = 0;

  Future<MemoryCrypto> _ensureCrypto() async {
    _crypto ??= await MemoryCrypto.demo();
    return _crypto!;
  }

  Future<List<MoodEntry>> getAll() async {
    if (_writesSuspended) return <MoodEntry>[];
    if (_storageUnconfirmed) throw const MoodSaveUnconfirmedException();
    final generation = _dataGeneration;
    return _readAll(generation);
  }

  Future<List<MoodEntry>> _readAll(int generation) async {
    if (!_isCurrent(generation)) return <MoodEntry>[];
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key) ?? '';
    if (raw.trim().isEmpty) return <MoodEntry>[];

    final crypto = await _ensureCrypto();
    if (!_isCurrent(generation)) return <MoodEntry>[];
    if (_storageUnconfirmed) throw const MoodSaveUnconfirmedException();
    try {
      final decrypted = await crypto.decryptJson(raw);
      if (!_isCurrent(generation)) return <MoodEntry>[];
      if (_storageUnconfirmed) throw const MoodSaveUnconfirmedException();
      final rows = decrypted['items'];
      if (rows is! List || rows.any((item) => item is! Map)) {
        throw const FormatException('Invalid mood history records.');
      }
      final items = rows
          .cast<Map>()
          .map((m) => MoodEntry.fromJson(Map<String, Object?>.from(m)))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return items;
    } catch (_) {
      if (!_isCurrent(generation)) return <MoodEntry>[];
      if (_storageUnconfirmed) throw const MoodSaveUnconfirmedException();
      // Only a genuine legacy JSON list is eligible for migration. A failed
      // encrypted envelope must remain untouched and surface as an error.
      final legacyJson = jsonDecode(raw);
      if (legacyJson is! List || legacyJson.any((item) => item is! Map)) {
        throw const FormatException('Stored mood history could not be read.');
      }
      final legacy = legacyJson
          .cast<Map>()
          .map((item) => MoodEntry.fromJson(Map<String, Object?>.from(item)))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (legacy.isNotEmpty) {
        await _persist(legacy, generation);
      }
      return _isCurrent(generation) ? legacy : <MoodEntry>[];
    }
  }

  Future<void> add(MoodEntry entry) {
    return _enqueueWrite((generation) async {
      final items = await _readAll(generation);
      _requireCurrent(generation);
      items.add(entry);
      // keep recent-ish size bounded
      if (items.length > 2000) {
        items.removeRange(0, items.length - 2000);
      }
      await _persist(items, generation);
      unawaited(HomeWidgetBridge.instance.refresh());
    });
  }

  Future<void> _persist(List<MoodEntry> items, int generation) async {
    _requireCurrent(generation);
    final crypto = await _ensureCrypto();
    _requireCurrent(generation);
    final blob = await crypto.encryptJson({
      'items': items.map((e) => e.toJson()).toList(),
    });
    _requireCurrent(generation);
    bool written;
    try {
      written = await NeuraPrefsCache.prefs.setString(_key, blob);
    } catch (_) {
      _requireCurrent(generation);
      _storageUnconfirmed = true;
      throw const MoodSaveUnconfirmedException();
    }
    if (!_isCurrent(generation)) {
      await NeuraPrefsCache.prefs.remove(_key);
      _requireCurrent(generation);
    }
    if (!written) {
      _storageUnconfirmed = true;
      throw const MoodSaveUnconfirmedException();
    }
    _requireCurrent(generation);
  }

  Future<MoodEntry?> latest() async {
    final items = await getAll();
    if (items.isEmpty) return null;
    return items.last;
  }

  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _dataGeneration += 1;
    Object? drainFailure;
    try {
      await _writeQueue.timeout(const Duration(seconds: 3));
    } catch (error) {
      drainFailure = error;
    }
    _crypto = null;
    _writeQueue = Future<void>.value();
    if (drainFailure != null) {
      throw StateError('Mood history writer shutdown could not be verified.');
    }
  }

  Future<T> _enqueueWrite<T>(
    Future<T> Function(int generation) operation,
  ) {
    if (_writesSuspended) {
      return Future<T>.error(StateError('Mood history writes are suspended.'));
    }
    if (_storageUnconfirmed) {
      return Future<T>.error(const MoodSaveUnconfirmedException());
    }
    final generation = _dataGeneration;
    Future<T> run() {
      _requireCurrent(generation);
      return operation(generation);
    }

    final next = _writeQueue.then<T>(
      (_) => run(),
      onError: (_) => run(),
    );
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  bool _isCurrent(int generation) =>
      !_writesSuspended && generation == _dataGeneration;

  void _requireCurrent(int generation) {
    if (!_isCurrent(generation)) {
      throw StateError('Mood history operation was invalidated.');
    }
    if (_storageUnconfirmed) throw const MoodSaveUnconfirmedException();
  }
}
