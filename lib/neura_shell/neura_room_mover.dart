// lib/neura_shell/neura_room_mover.dart
//
// Lets Neura move between the rooms of her home on her own.
//
// The model asks to move with the `dispatch_intent` tool. The move waits
// until the reply that asked for it has finished, so a reply is always
// generated, spoken and logged under the rules of the room it started in.
// A reply that is stopped, fails or is replaced drops its pending move.
// No move happens in Safe Mode, and every move can be undone.

import '../services/neura_chat_policy.dart';
import 'models/neura_room.dart';

/// A finished move Neura chose for herself.
class NeuraSelfMove {
  const NeuraSelfMove({required this.from, required this.to});

  final NeuraRoom from;
  final NeuraRoom to;
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

  /// The room waiting for its reply to finish, if any.
  NeuraRoom? get pending => _pending;

  /// Records Neura's wish to move to [roomId] once the reply [owner]
  /// finishes. Returns whether she will move (or is already there).
  bool request(String roomId, {required Object owner}) {
    if (_safeMode()) return false;
    if (!NeuraChatPolicy.knownRoomIds.contains(roomId)) return false;
    final target = NeuraRoom.fromId(roomId);
    if (target.id != roomId) return false;
    if (target.id == _currentRoom().id) {
      drop(owner);
      return true;
    }
    _pending = target;
    _owner = owner;
    return true;
  }

  /// Makes the pending move for the reply [owner], if it still applies.
  Future<NeuraSelfMove?> settle(Object owner) async {
    final target = _pending;
    if (target == null || _owner != owner) return null;
    _pending = null;
    _owner = null;
    if (_safeMode()) return null;
    final from = _currentRoom();
    if (from.id == target.id) return null;
    await _setRoom(target);
    return NeuraSelfMove(from: from, to: target);
  }

  /// Forgets the pending move for the reply [owner] without moving.
  void drop(Object owner) {
    if (_owner != owner) return;
    _pending = null;
    _owner = null;
  }

  /// Takes Neura back to where she was before [move], if she is still in
  /// the room she moved to.
  Future<bool> undo(NeuraSelfMove move) async {
    if (_currentRoom().id != move.to.id) return false;
    await _setRoom(move.from);
    return true;
  }
}
