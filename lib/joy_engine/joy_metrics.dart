import '../core/memory/memory_graph_service.dart';
import 'joy_types.dart';

class JoyMetrics {
  Future<void> logResult(JoyMoment moment, {required String result}) async {
    try {
      await MemoryGraphService.I.logSuggestion(
        kind: 'JOY_MOMENT',
        payload: {'id': moment.id, 'title': moment.title, 'type': moment.type.name},
        outcome: result,
      );
    } catch (_) {
      // Metrics are a nice-to-have; never let a log failure surface to the UI.
    }
  }
}
