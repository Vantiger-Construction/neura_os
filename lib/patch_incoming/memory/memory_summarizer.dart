import 'memory_models.dart';

/// Produces text summaries of memory collections.
class MemorySummarizer {
  /// Summarize the most recent [count] memories into a short paragraph.
  String summarize(List<MemoryNode> nodes, {int count = 5}) {
    if (nodes.isEmpty) return 'No memories recorded yet.';

    final sorted = [...nodes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recent = sorted.take(count);
    final snippets = recent.map((n) => n.content).join(' | ');
    return 'Recent: $snippets';
  }
}
