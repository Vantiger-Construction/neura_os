import 'dart:convert';
import 'neura_bus.dart';
import '../startup/neura_prefs_cache.dart';

class NeuraRoomMemoryItem {
  final DateTime at;
  final String tag;
  final String summary;
  final Map<String, dynamic> data;

  NeuraRoomMemoryItem({
    required this.at,
    required this.tag,
    required this.summary,
    Map<String, dynamic>? data,
  }) : data = data ?? const {};

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'tag': tag,
        'summary': summary,
        'data': data,
      };

  static NeuraRoomMemoryItem fromJson(Map<String, dynamic> j) => NeuraRoomMemoryItem(
        at: DateTime.parse(j['at'] as String),
        tag: j['tag'] as String,
        summary: j['summary'] as String,
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// Small, capped, room-scoped memory store.
///
/// This intentionally keeps the payload tiny to avoid accidental PII retention.
class NeuraRoomMemory {
  NeuraRoomMemory._();
  static final NeuraRoomMemory I = NeuraRoomMemory._();

  static const _kKey = 'neura_room_memory_v1';
  static const int maxPerRoom = 6;
  static const int maxTotal = 80;

  final Map<String, List<NeuraRoomMemoryItem>> _byRoom = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final sp = NeuraPrefsCache.prefs;
    final raw = sp.getString(_kKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final obj = json.decode(raw) as Map<String, dynamic>;
      obj.forEach((roomKey, v) {
        final list = (v as List)
            .cast<Map>()
            .map((e) => NeuraRoomMemoryItem.fromJson(e.cast<String, dynamic>()))
            .toList();
        _byRoom[roomKey] = list;
      });
    }
    _loaded = true;
  }

  Future<void> save() async {
    final sp = NeuraPrefsCache.prefs;
    final obj = <String, dynamic>{};
    _byRoom.forEach((room, items) {
      obj[room] = items.map((e) => e.toJson()).toList();
    });
    await sp.setString(_kKey, json.encode(obj));
  }

  String _roomKey(NeuraRoomKey room) => room.toString();

  List<NeuraRoomMemoryItem> list(NeuraRoomKey room) {
    final k = _roomKey(room);
    return List.unmodifiable(_byRoom[k] ?? const []);
  }

  Future<void> remember({
    required NeuraRoomKey room,
    required String tag,
    required String summary,
    Map<String, dynamic>? data,
  }) async {
    await load();
    final k = _roomKey(room);
    final list = (_byRoom[k] ??= <NeuraRoomMemoryItem>[]);

    final clean = summary.trim();
    list.insert(
      0,
      NeuraRoomMemoryItem(
        at: DateTime.now(),
        tag: tag,
        summary: clean.length > 100 ? clean.substring(0, 100) : clean,
        data: data,
      ),
    );

    if (list.length > maxPerRoom) list.removeRange(maxPerRoom, list.length);

    final all = _byRoom.values.expand((e) => e).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    if (all.length > maxTotal) {
      final keep = all.take(maxTotal).toSet();
      _byRoom.forEach((roomId, items) {
        items.removeWhere((x) => !keep.contains(x));
      });
    }

    await save();
  }

  /// Short "welcome back" line based on the most recent memory in a room.
  String? composeReturnLine(NeuraRoomKey room) {
    final items = list(room);
    if (items.isEmpty) return null;

    final top = items.first;
    switch (top.tag) {
      case 'saved_dream':
        return 'Back to Dream Atrium — last time you saved a dream. Want to build on it?';
      case 'mood_checkin':
        return 'Mood Den again — last check‑in is logged. Want a quick update?';
      case 'error':
        return "We had a hiccup last time. I've got my multiverse wrench ready.";
      case 'success':
        return "Nice — last time you made progress here. Let's keep it moving.";
      default:
        return 'Welcome back — I remember what we were doing here.';
    }
  }

  void resetAfterDataWipe() {
    _byRoom.clear();
    _loaded = false;
  }
}
