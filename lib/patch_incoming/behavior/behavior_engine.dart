import '../memory/memory_core.dart';
import '../emotion/emotion_core.dart';
import 'context_snapshot.dart';

/// A decision produced by the behavior engine.
class BehaviorDecision {
  final String action;
  final Map<String, dynamic> params;

  const BehaviorDecision({required this.action, this.params = const {}});
}

/// Decides Neura's next behavior/action based on context, memory, and emotion.
class BehaviorEngine {
  final MemoryCore memoryCore;
  final EmotionCore emotionCore;

  BehaviorEngine({required this.memoryCore, required this.emotionCore});

  Future<void> init() async {
    // No-op for now; reserved for model loading or rule initialization.
  }

  Future<BehaviorDecision> decideNext({
    required ContextSnapshot context,
  }) async {
    // Stub: returns a default idle decision.
    return const BehaviorDecision(action: 'idle');
  }
}
