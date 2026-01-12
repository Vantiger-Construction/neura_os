import 'dart:async';

import 'neura_bus.dart';
import 'neura_room_memory.dart';

/// Background watcher that listens to bus events and writes memory records.
///
/// This singleton should be started once during app startup. It observes
/// success, error and prompt events and stores them via [NeuraRoomMemory].
class NeuraMemoryWatcher {
  NeuraMemoryWatcher._();
  static final NeuraMemoryWatcher instance = NeuraMemoryWatcher._();

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await NeuraRoomMemory.instance.load();
    NeuraBus.instance.stream.listen((event) async {
      final room = event.room ?? NeuraBus.instance.currentRoom;
      switch (event.type) {
        case NeuraEventType.error:
          await NeuraRoomMemory.instance.remember(
            room: room,
            tag: 'error',
            summary: event.message ?? 'Error occurred',
            data: event.data,
          );
          break;
        case NeuraEventType.success:
          await NeuraRoomMemory.instance.remember(
            room: room,
            tag: 'success',
            summary: event.message ?? 'Success',
            data: event.data,
          );
          break;
        case NeuraEventType.prompt:
          await NeuraRoomMemory.instance.remember(
            room: room,
            tag: 'prompt',
            summary: event.message ?? 'Prompt',
            data: event.data,
          );
          break;
        default:
          break;
      }
    });
  }
}
