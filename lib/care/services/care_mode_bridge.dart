import 'dart:convert';

import '../../after_storm/models/storm_event.dart';
import '../../startup/neura_prefs_cache.dart';

/// Bridge so AfterStormService can fan events into Care Mode.
///
/// Every storm event is persisted to SharedPreferences.  Events flagged as
/// [StormEvent.safetyRisk] are additionally surfaced through [safetyAlerts].

class CareModeBridge {
  CareModeBridge._internal();
  static final CareModeBridge instance = CareModeBridge._internal();

  static const String _keyEvents = 'care_storm_events_v1';
  static const int _maxStored = 100;

  List<StormEvent> _events = [];
  bool _loaded = false;
  bool _writesSuspended = false;
  int _dataGeneration = 0;
  Future<void> _writeQueue = Future<void>.value();

  /// All persisted storm events, newest first.
  List<StormEvent> get events => List.unmodifiable(_events);

  /// Subset of [events] that carry a safety-risk flag.
  List<StormEvent> get safetyAlerts =>
      _events.where((e) => e.safetyRisk).toList(growable: false);

  /// Ensures events are loaded from storage before use.
  Future<void> load() async {
    if (_loaded || _writesSuspended) return;
    final generation = _dataGeneration;
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_keyEvents);
    if (!_isCurrent(generation)) return;
    if (raw != null) {
      try {
        final list = json.decode(raw) as List<dynamic>;
        final loaded = list
            .whereType<Map<String, dynamic>>()
            .map((m) => StormEvent.fromMap(m))
            .toList();
        if (!_isCurrent(generation)) return;
        _events = loaded;
      } catch (_) {
        if (!_isCurrent(generation)) return;
        _events = [];
        await prefs.remove(_keyEvents);
      }
    }
    if (!_isCurrent(generation)) return;
    _loaded = true;
  }

  /// Records [event] in-memory and persists it to SharedPreferences.
  ///
  /// Trims the list to [_maxStored] most-recent entries so storage
  /// does not grow unbounded.
  Future<void> logStormEvent(StormEvent event) {
    if (_writesSuspended) return Future<void>.value();
    final generation = _dataGeneration;
    final next = _writeQueue.then((_) async {
      if (!_isCurrent(generation)) return;
      await load();
      if (!_isCurrent(generation)) return;
      _events.insert(0, event);
      if (_events.length > _maxStored) {
        _events = _events.sublist(0, _maxStored);
      }
      await _persist(generation);
    });
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  /// Removes all stored storm events.
  Future<void> clearAll() async {
    _events = [];
    final prefs = NeuraPrefsCache.prefs;
    await prefs.remove(_keyEvents);
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
    _events = [];
    _loaded = false;
    _writeQueue = Future<void>.value();
    if (drainFailure != null) {
      throw StateError('Care history writer shutdown could not be verified.');
    }
  }

  Future<void> _persist(int generation) async {
    if (!_isCurrent(generation)) return;
    final prefs = NeuraPrefsCache.prefs;
    final list = _events.map((e) => e.toMap()).toList();
    if (!_isCurrent(generation)) return;
    await prefs.setString(_keyEvents, json.encode(list));
    if (!_isCurrent(generation)) await prefs.remove(_keyEvents);
  }

  bool _isCurrent(int generation) =>
      !_writesSuspended && generation == _dataGeneration;
}
