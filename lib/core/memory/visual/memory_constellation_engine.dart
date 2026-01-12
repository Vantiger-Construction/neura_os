import '../memory_models.dart';
import 'memory_timeline_node.dart';
import 'dart:math';

class MemoryConstellationEngine {
  List<MemoryTimelineNode> generate(List<MemoryNode> memories) {
    final rand = Random(42);
    return memories.map((m) {
      return MemoryTimelineNode(
        memory: m,
        x: rand.nextDouble(),
        y: rand.nextDouble(),
      );
    }).toList();
  }
}
