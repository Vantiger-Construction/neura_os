// lib/neura_shell/neura_room_mover.dart
//
// Lets Neura move between the rooms of her home on her own.
//
// The model asks to move with the `dispatch_intent` tool. The move waits
// until the reply that asked for it has finished, so a reply is always
// generated, spoken and logged under the rules of the room it started in.
// A reply that is stopped, fails or is replaced drops its pending move.
// No move happens in Safe Mode, and every move can be undone.
//
// The user always wins: any room change the mover sees after a request
// (the user picking a room, a voice command, another move) bumps a
// revision, and a pending move or an Undo from an older revision does
// nothing. Call [NeuraRoomMover.observe] whenever the shell's room may have
// changed.

import '../services/neura_chat_policy.dart';
import 'models/neura_room.dart';

/// A finished move Neura chose for herself.
class NeuraSelfMove {
  const NeuraSelfMove({
    required this.from,
    required this.to,
    required this.revision,
    this.error,
  });

  final NeuraRoom from;
  final NeuraRoom to;

  /// The room revision right after this move; Undo needs it unchanged.
  final int revision;

  /// Set when the shell reached [to] but part of its room setup failed.
  final Object? error;
}

class NeuraRoomMover {
  NeuraRoomMover({
    required NeuraRoom Function() currentRoom,
    required Future<void> Function(NeuraRoom room) setRoom,
    required bool Function() safeMode,
  })  : _currentRoom = currentRoom,
        _setRoom = setRoom,
        _safeMode = safeMode;

  final NeuraRoom Function() _currentRoom;
  final Future<void> Function(NeuraRoom room) _setRoom;
  final bool Function() _safeMode;

  NeuraRoom? _pending;
  Object? _owner;
  int _pendingRevision = 0;
  int _revision = 0;
  String? _seenRoomId;

  /// The room waiting for its reply to finish, if any.
  NeuraRoom? get pending => _pending;

  /// Counts the room changes seen so far.
  int get revision => _revision;

  /// Records the shell's current [room], counting a change of room.
  void observe(NeuraRoom room) {
    final seen = _seenRoomId;
    _seenRoomId = room.id;
    if (seen != null && seen != room.id) _revision++;
  }

  /// Records Neura's wish to move to [roomId] once the reply [owner]
  /// finishes. Returns true only when a move is now queued; a request for
  /// the room she is already in, an unknown room or Safe Mode returns false
  /// and leaves any queued move alone.
  bool request(String roomId, {required Object owner}) {
    if (_safeMode()) return false;
    if (!NeuraChatPolicy.knownRoomIds.contains(roomId)) return false;
    final target = NeuraRoom.fromId(roomId);
    if (target.id != roomId) return false;
    final current = _currentRoom();
    observe(current);
    if (target.id == current.id) return false;
    _pending = target;
    _owner = owner;
    _pendingRevision = _revision;
    return true;
  }

  /// Makes the pending move for the reply [owner], if it still applies.
  ///
  /// Returns null when there is nothing to do, when the room changed since
  /// the request, or when the shell did not end up in the target room. If
  /// the shell did reach the target but its setup threw, the move is still
  /// returned (with [NeuraSelfMove.error]) so it can be undone. If the shell
  /// did not move and setup threw, the error is rethrown.
  Future<NeuraSelfMove?> settle(Object owner) async {
    final target = _pending;
    if (target == null || _owner != owner) return null;
    _pending = null;
    _owner = null;
    if (_safeMode()) return null;
    final from = _currentRoom();
    observe(from);
    if (_revision != _pendingRevision || from.id == target.id) return null;

    Object? error;
    StackTrace? stack;
    try {
      await _setRoom(target);
    } catch (e, s) {
      error = e;
      stack = s;
    }
    final now = _currentRoom();
    observe(now);
    if (now.id != target.id) {
      if (error != null) Error.throwWithStackTrace(error, stack!);
      return null;
    }
    return NeuraSelfMove(
      from: from,
      to: target,
      revision: _revision,
      error: error,
    );
  }

  /// Forgets the pending move for the reply [owner] without moving.
  void drop(Object owner) {
    if (_owner != owner) return;
    _pending = null;
    _owner = null;
  }

  /// Takes Neura back to where she was before [move]. Does nothing once any
  /// other room change has happened since the move. Returns whether she is
  /// back in the room she left.
  Future<bool> undo(NeuraSelfMove move) async {
    observe(_currentRoom());
    if (_revision != move.revision) return false;
    try {
      await _setRoom(move.from);
    } finally {
      observe(_currentRoom());
    }
    return _currentRoom().id == move.from.id;
  }
}
