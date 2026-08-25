import 'dart:async';

/// Neura's global event bus.
///
/// Purpose:
/// - Screens/modules publish intent/state changes without importing Neura UI.
/// - Neura shell (avatar/voice/memory/timeline) subscribes once and reacts.
///
/// Rule: keep events small + non-sensitive.

enum NeuraRoomKey {
  penthouse,
  reflectionBay,
  joyLounge,
  moodDen,
  dreamAtrium,
  legacyVault,
  settings,
}

enum NeuraEventType {
  roomEnter,
  roomExit,
  userTypingStart,
  userTypingStop,
  userIdle,
  userActive,
  error,
  success,
  prompt,
  voiceRequest,
}

class NeuraEvent {
  final NeuraEventType type;
  final NeuraRoomKey? room;
  final String? message;
  final Map<String, dynamic> data;

  NeuraEvent(
    this.type, {
    this.room,
    this.message,
    Map<String, dynamic>? data,
  }) : data = data ?? const {};
}

/// Simple ring buffer for timeline/debug.
class NeuraEventLog {
  final int max;
  final List<NeuraEvent> _items = <NeuraEvent>[];

  NeuraEventLog({this.max = 200});

  List<NeuraEvent> get items => List.unmodifiable(_items);

  void add(NeuraEvent e) {
    _items.insert(0, e);
    if (_items.length > max) _items.removeRange(max, _items.length);
  }

  void clear() => _items.clear();
}

class NeuraBus {
  NeuraBus._();
  static final NeuraBus I = NeuraBus._();

  final _events = StreamController<NeuraEvent>.broadcast();
  Stream<NeuraEvent> get stream => _events.stream;

  final NeuraEventLog log = NeuraEventLog(max: 240);

  NeuraRoomKey currentRoom = NeuraRoomKey.penthouse;

  void emit(NeuraEvent e) {
    log.add(e);
    _events.add(e);
  }

  void enterRoom(NeuraRoomKey room) {
    emit(NeuraEvent(NeuraEventType.roomExit, room: currentRoom));
    currentRoom = room;
    emit(NeuraEvent(NeuraEventType.roomEnter, room: room));
  }

  void resetAfterDataWipe() {
    log.clear();
    currentRoom = NeuraRoomKey.penthouse;
  }
}
