import 'memory_models.dart';

class LongTermMemory {
  final List<MemoryNode> _archive = [];

  void archive(MemoryNode node) {
    if (node.weight > 0.75) {
      _archive.add(node.copyWith(weight: node.weight * 0.9));
    }
  }

  List<MemoryNode> get archive => List.unmodifiable(_archive);
}
