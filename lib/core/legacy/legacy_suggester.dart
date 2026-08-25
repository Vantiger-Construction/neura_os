import '../memory/memory_models.dart';

class LegacySuggester {
  bool shouldSuggest(MemoryNode node) {
    return node.weight > 0.7 && node.tags.contains('emotion');
  }
}
