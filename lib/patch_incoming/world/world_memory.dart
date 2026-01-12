import '../memory/memory_core.dart';
import '../memory/memory_models.dart';
import '../behavior/neura_room.dart';

class WorldMemory {
  final MemoryCore memory;

  WorldMemory({required this.memory});

  Future<void> noteRoomEvent({
    required NeuraRoom room,
    required String note,
  }) async {
    await memory.addMemory(
      type: MemoryType.note,
      content: 'Room ${room.name}: $note',
      initialWeight: 0.5,
      tags: ['room', room.name],
    );
  }

  List<MemoryNode> memoriesForRoom(NeuraRoom room) {
    return memory.all
        .where((m) => m.tags.contains(room.name))
        .toList();
  }
}
