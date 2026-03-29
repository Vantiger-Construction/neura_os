import 'memory_models.dart';
import 'memory_store.dart';

/// Central memory system: stores and retrieves MemoryNodes.
class MemoryCore {
  final MemoryStore _store = MemoryStore();
  List<MemoryNode> _nodes = [];

  List<MemoryNode> get all => List.unmodifiable(_nodes);

  Future<void> init() async {
    _nodes = await _store.load();
  }

  Future<void> addMemory({
    required MemoryType type,
    required String content,
    double initialWeight = 0.5,
    List<String> tags = const [],
  }) async {
    final node = MemoryNode(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      content: content,
      weight: initialWeight,
      tags: tags,
      createdAt: DateTime.now(),
    );
    _nodes.add(node);
    await _store.save(_nodes);
  }

  List<MemoryNode> search(String query) {
    final lower = query.toLowerCase();
    return _nodes
        .where(
          (n) =>
              n.content.toLowerCase().contains(lower) ||
              n.tags.any((t) => t.toLowerCase().contains(lower)),
        )
        .toList();
  }
}
