import 'dart:async';
import 'dart:developer' as developer;

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

    await NeuraRoomMemory.I.load();

    _sub = NeuraBus.I.stream.listen((event) {
      unawaited(_handleEvent(event));
    });
    _started = true;
  }

  Future<void> _handleEvent(NeuraEvent event) async {
    try {
      final room = event.room ?? NeuraBus.I.currentRoom;
      switch (event.type) {
        case NeuraEventType.error:
          await NeuraRoomMemory.I.remember(
            room: room,
            tag: 'error',
            summary: (event.message ?? 'Error occurred'),
            data: event.data,
          );
          break;
        case NeuraEventType.success:
          await NeuraRoomMemory.I.remember(
            room: room,
            tag: 'success',
            summary: (event.message ?? 'Success'),
            data: event.data,
          );
          break;
        case NeuraEventType.prompt:
          await NeuraRoomMemory.I.remember(
            room: room,
            tag: 'prompt',
            summary: (event.message ?? 'Prompt'),
            data: event.data,
          );
          break;
        default:
          break;
      }
    } catch (error, stackTrace) {
      developer.log(
        'Neura memory watcher event failed',
        name: 'neura.memory',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
