import 'legacy_suggester.dart';
import 'legacy_engine.dart';
import '../memory/memory_models.dart';

class LegacyBridge {
  final LegacySuggester suggester;
  final LegacyEngine engine;

  LegacyBridge(this.suggester, this.engine);

  void evaluate(MemoryNode node) {
    if (suggester.shouldSuggest(node)) {
      engine.record(
        "Neura suggested preserving this moment: ${node.content}",
      );
    }
  }
}
