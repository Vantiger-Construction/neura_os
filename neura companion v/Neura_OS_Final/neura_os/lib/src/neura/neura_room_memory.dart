import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'neura_bus.dart';

/// Representation of a single memory item stored for a room.
///
/// Only a short [tag] and [summary] are stored along with an optional
/// arbitrary [data] map. Memories are ordered by time, most recent first.
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

  static NeuraRoomMemoryItem fromJson(Map<String, dynamic> j) {
    return NeuraRoomMemoryItem(
      at: DateTime.parse(j['at'] as String),
      tag: j['tag'] as String,
      summary: j['summary'] as String,
      data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// Persistent store for per‑room memory.
///
/// This singleton manages reading and writing a bounded list of memory
/// items per room from [SharedPreferences]. See [maxPerRoom] and [maxTotal].
class NeuraRoomMemory {
  NeuraRoomMemory._();
  static final NeuraRoomMemory instance = NeuraRoomMemory._();

  static const String _kKey = 'neura_room_memory_v1';
  static const int maxPerRoom = 6;
  static const int maxTotal = 80;

  final Map<String, List<NeuraRoomMemoryItem>> _byRoom = {};
  bool _loaded = false;

  String _roomKey(NeuraRoom room) => room.toString();

  /// Load from persistent storage the current memory cache.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final obj = json.decode(raw) as Map<String, dynamic>;
      obj.forEach((roomKey, v) {
        final list = (v as List)
            .cast<Map>()
            .map((e) =>
                NeuraRoomMemoryItem.fromJson(e.cast<String, dynamic>()))
            .toList();
        _byRoom[roomKey] = list;
      });
    }
    _loaded = true;
  }

  /// Save the current memory cache to persistent storage.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final obj = <String, dynamic>{};
    _byRoom.forEach((room, items) {
      obj[room] = items.map((e) => e.toJson()).toList();
    });
    await prefs.setString(_kKey, json.encode(obj));
  }

  /// List the memory items stored for a given [room].
  List<NeuraRoomMemoryItem> list(NeuraRoom room) {
    final k = _roomKey(room);
    return List.unmodifiable(_byRoom[k] ?? const []);
  }

  /// Append a new memory item for a [room], trimming per‑room and global caps.
  Future<void> remember({
    required NeuraRoom room,
    required String tag,
    required String summary,
    Map<String, dynamic>? data,
  }) async {
    await load();
    final k = _roomKey(room);
    final list = (_byRoom[k] ??= <NeuraRoomMemoryItem>[]);
    list.insert(
      0,
      NeuraRoomMemoryItem(
        at: DateTime.now(),
        tag: tag,
        summary: summary,
        data: data,
      ),
    );
    if (list.length > maxPerRoom) {
      list.removeRange(maxPerRoom, list.length);
    }
    final all = _byRoom.values.expand((x) => x).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    if (all.length > maxTotal) {
      final keep = all.take(maxTotal).toSet();
      _byRoom.forEach((roomKey, items) {
        items.removeWhere((x) => !keep.contains(x));
      });
    }
    await save();
  }

  /// Compose a short phrase to display when re‑entering a [room].
  ///
  /// Depending on the most recent [tag], different text is returned. If there
  /// is no memory, returns null.
  String? composeReturnLine(NeuraRoom room) {
    final items = list(room);
    if (items.isEmpty) return null;
    final top = items.first;
    switch (top.tag) {
      case 'saved_dream':
        return 'Back to Dream Bay — last time you saved a dream.';
      case 'mood_checkin':
        return 'Mood Den again — last check‑in is logged.';
      case 'error':
        return 'We had a hiccup last time. Ready to retry.';
      case 'success':
        return 'Nice — last time you made progress here.';
      case 'prompt':
        return top.summary;
      default:
        return 'Welcome back — I remember what we were doing here.';
    }
  }
}
