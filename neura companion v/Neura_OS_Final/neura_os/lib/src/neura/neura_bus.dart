import 'dart:async';

/// Enumeration of high-level rooms in the Neura OS.
///
/// This is intentionally coarse grained; modules can map their own screen to
/// one of these rooms to influence Neura's tone and memory cues.
enum NeuraRoom {
  dashboard,
  moodDen,
  dreamBay,
  reflectionBay,
  joyLounge,
  legacyVault,
  settings,
}

/// Types of events that can be emitted on the NeuraBus.
///
/// These are intentionally generic; they cover navigation, user activity,
/// successes, errors and prompts. Consumers of the bus can decide how to
/// interpret each event.
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

/// Event payload posted to the NeuraBus.
///
/// At minimum an event has a [type]. Some events optionally include a
/// [room], a human friendly [message] or arbitrary [data].
class NeuraEvent {
  final NeuraEventType type;
  final NeuraRoom? room;
  final String? message;
  final Map<String, dynamic> data;

  NeuraEvent(this.type, {this.room, this.message, Map<String, dynamic>? data})
      : data = data ?? const {};
}

/// Global event bus used to coordinate the OS‑level Neura behaviour.
///
/// This singleton exposes a [stream] of events and allows emitting new events.
/// It also maintains the currently active [currentRoom] so that events can
/// implicitly refer to a room.
class NeuraBus {
  NeuraBus._();

  static final NeuraBus instance = NeuraBus._();

  final _events = StreamController<NeuraEvent>.broadcast();

  /// Broadcast stream of all events.
  Stream<NeuraEvent> get stream => _events.stream;

  /// The room that is currently active. Defaults to [NeuraRoom.dashboard].
  NeuraRoom currentRoom = NeuraRoom.dashboard;

  /// Emit an event to all listeners.
  void emit(NeuraEvent e) {
    _events.add(e);
  }

  /// Update the [currentRoom], emitting exit and enter events.
  void enterRoom(NeuraRoom room) {
    if (currentRoom != room) {
      emit(NeuraEvent(NeuraEventType.roomExit, room: currentRoom));
      currentRoom = room;
      emit(NeuraEvent(NeuraEventType.roomEnter, room: room));
    }
  }
}
