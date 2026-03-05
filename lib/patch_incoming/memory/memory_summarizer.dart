import 'memory_models.dart';

/// Summarizes memories for quick recall
class MemorySummarizer {
  /// Generate a summary from a list of memories
  Future<String> summarize(List<Memory> memories) async {
    if (memories.isEmpty) {
      return 'No memories to summarize.';
    }
    
    // Simple summarization: combine recent memories
    final recentCount = memories.length > 5 ? 5 : memories.length;
    final recent = memories.take(recentCount);
    
    final snippets = recent.map((m) {
      final content = m.content;
      return content.length > 100 
          ? '${content.substring(0, 97)}...' 
          : content;
    }).join(' | ');
    
    return 'Recent: $snippets';
  }
  
  /// Extract key themes from memories
  Future<List<String>> extractThemes(List<Memory> memories) async {
    // TODO: Implement more sophisticated theme extraction
    return ['general', 'conversation', 'activity'];
  }
}
