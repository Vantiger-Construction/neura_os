import '../../../memory/memory_models.dart';

/// A positioned memory node for visual rendering (constellation view).
class MemoryTimelineNode {
  final MemoryNode memory;
  final double x; // 0.0–1.0 normalized position
  final double y; // 0.0–1.0 normalized position

  const MemoryTimelineNode({
    required this.memory,
    required this.x,
    required this.y,
  });
}
