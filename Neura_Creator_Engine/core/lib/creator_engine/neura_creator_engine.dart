import 'models/content_item.dart';
import 'services/content_backend.dart';
import 'services/creator_ports.dart';
import 'services/local_template_backend.dart';

class NeuraCreatorEngine {
  final MemoryGraphPort memory;
  final GuardrailsPort guardrails;
  final ContentBackend backend;

  NeuraCreatorEngine({
    required this.memory,
    required this.guardrails,
    ContentBackend? backend,
  }) : backend = backend ?? LocalTemplateBackend();

  /// Generate a single approved content item (or null if blocked).
  Future<NeuraContentItem?> generate({int candidates = 5}) async {
    final signals = await memory.getRecentSignals();
    final cands = await backend.generateCandidates(signals: signals, count: candidates);

    for (final item in cands) {
      final draft = item.toJson();
      final approved = await guardrails.approveContent(draft);
      if (approved == null) continue;

      // Log offer to memory graph for outcome learning.
      await memory.logEvent('content_offered', {
        'contentId': approved['id'],
        'type': approved['type'],
        'title': approved['title'],
        'signals': signals,
        'ts': DateTime.now().toIso8601String(),
      });

      return NeuraContentItem.fromJson(approved);
    }

    return null;
  }

  Future<void> logOutcome({
    required NeuraContentItem item,
    required String outcome, // accepted|declined|completed|saved
    Map<String, dynamic> extra = const {},
  }) async {
    await memory.logEvent('content_outcome', {
      'contentId': item.id,
      'type': item.type.name,
      'outcome': outcome,
      'ts': DateTime.now().toIso8601String(),
      ...extra,
    });
  }
}
