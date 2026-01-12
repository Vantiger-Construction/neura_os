import '../core/content/content_engine.dart';
import '../core/intent/intent_engine.dart';
import '../core/memory/memory_graph_service.dart';

/// Central access point for the new core engines.
///
/// Kept optional so existing UI can adopt gradually without breaking routes.
class NeuraCoreServices {
  static final NeuraCoreServices I = NeuraCoreServices._();
  NeuraCoreServices._();

  final MemoryGraphService memory = MemoryGraphService.I;
  late final IntentEngine intents = IntentEngine(memory);
  final ContentEngine content = ContentEngine();
}
