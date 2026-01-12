import 'dart:async';
import 'intent_vector.dart';
import 'intent_weaver.dart';
import '../memory/memory_graph_service.dart';

class IntentEngine {
  final MemoryGraphService memory;
  final IntentWeaver weaver = IntentWeaver();
  late final StreamSubscription _sub;

  IntentEngine(this.memory) {
    _sub = weaver.weaves.listen((weave) async {
      // Log that a weave opportunity occurred.
      await memory.logSuggestion(
        kind: 'BEGIN_WEAVE',
        payload: {'intent': weave.intent.name},
      );
    });
  }

  Future<void> demoCheckIn() async {
    // Fake a perception reading.
    const vec = IntentVector({
      NeuraIntent.seekingCalm: 0.7,
      NeuraIntent.seekingProgress: 0.2,
      NeuraIntent.seekingSleep: 0.05,
      NeuraIntent.seekingConnection: 0.05,
    });

    await memory.logUserAction(
      kind: 'CHECK_IN',
      payload: {'mood': 'calm', 'energy': 0.6},
    );

    weaver.onIntent(vec);
  }

  void dispose() {
    _sub.cancel();
    weaver.dispose();
  }
}
