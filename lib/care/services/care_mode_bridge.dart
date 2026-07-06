import 'dart:convert';
import '../../after_storm/models/storm_event.dart';
/// Bridge so AfterStormService can fan events into Care Mode.
///
/// Every storm event is persisted to SharedPreferences.  Events flagged as
/// [StormEvent.safetyRisk] are additionally surfaced through [safetyAlerts].
import '../../startup/neura_prefs_cache.dart';

class CareModeBridge {
  CareModeBridge._internal();
  static final CareModeBridge instance = CareModeBridge._internal();

  static const String _keyEvents = 'care_storm_events_v1';
  static const int _maxStored = 100;

  List<StormEvent> _events = [];
  bool _loaded = false;

  /// All persisted storm events, newest first.
  List<StormEvent> get events =>
      List.unmodifiable(_events);

  /// Subset of [events] that carry a safety-risk flag.
  List<StormEvent> get safetyAlerts =>
      _events.where((e) => e.safetyRisk).toList(growable: false);

  /// Ensures events are loaded from storage before use.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_keyEvents);
    if (raw != null) {
      try {
        final list = json.decode(raw) as List<dynamic>;
        _events = list
            .whereType<Map<String, dynamic>>()
            .map((m) => StormEvent.fromMap(m))
            .toList();
      } catch (_) {
        _events = [];
        await prefs.remove(_keyEvents);
      }
    }
    _loaded = true;
  }

  /// Records [event] in-memory and persists it to SharedPreferences.
  ///
  /// Trims the list to [_maxStored] most-recent entries so storage
  /// does not grow unbounded.
  Future<void> logStormEvent(StormEvent event) async {
    await load();
    _events.insert(0, event);
    if (_events.length > _maxStored) {
      _events = _events.sublist(0, _maxStored);
    }
    await _persist();
  }

  /// Removes all stored storm events.
  Future<void> clearAll() async {
    _events = [];
    final prefs = NeuraPrefsCache.prefs;
    await prefs.remove(_keyEvents);
  }

  Future<void> _persist() async {
    final prefs = NeuraPrefsCache.prefs;
    final list = _events.map((e) => e.toMap()).toList();
    await prefs.setString(_keyEvents, json.encode(list));
  }
}
