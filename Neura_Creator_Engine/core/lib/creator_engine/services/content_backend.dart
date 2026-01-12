import '../models/content_item.dart';

/// Backend that produces candidate content items.
///
/// Default implementation in this module is LocalTemplateBackend (offline).
/// You can later swap in an LLM-backed backend (on-device or server) as long
/// as you keep outputs short and route through Guardrails.
abstract class ContentBackend {
  Future<List<NeuraContentItem>> generateCandidates({
    required Map<String, dynamic> signals,
    int count = 5,
  });
}
