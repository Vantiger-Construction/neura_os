import 'dart:async';

import 'neura_bus.dart';
import 'neura_room_memory.dart';

/// Listens to global events and stores small room memories.
class NeuraMemoryWatcher {
  NeuraMemoryWatcher._();
  static final NeuraMemoryWatcher I = NeuraMemoryWatcher._();

  bool _started = false;
  StreamSubscription<NeuraEvent>? _sub;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await NeuraRoomMemory.I.load();

    _sub = NeuraBus.I.stream.listen((e) async {
      final room = e.room ?? NeuraBus.I.currentRoom;
      switch (e.type) {
        case NeuraEventType.error:
          await NeuraRoomMemory.I.remember(
            room: room,
            tag: 'error',
            summary: (e.message ?? 'Error occurred'),
            data: e.data,
          );
          break;
        case NeuraEventType.success:
          await NeuraRoomMemory.I.remember(
            room: room,
            tag: 'success',
            summary: (e.message ?? 'Success'),
            data: e.data,
          );
          break;
        case NeuraEventType.prompt:
          await NeuraRoomMemory.I.remember(
            room: room,
            tag: 'prompt',
            summary: (e.message ?? 'Prompt'),
            data: e.data,
          );
          break;
        default:
          break;
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
