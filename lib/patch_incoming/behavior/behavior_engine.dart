import '../memory/memory_core.dart';
import '../emotion/emotion_core.dart';
import 'context_snapshot.dart';

/// A decision produced by the behavior engine.
class BehaviorDecision {
  final String action;
  final Map<String, dynamic> params;

  const BehaviorDecision({required this.action, this.params = const {}});

  @override
  String toString() => 'BehaviorDecision(action: $action, params: $params)';
}

/// Action constants shared between [BehaviorEngine] and [NeuraPresenceController].
abstract class BehaviorAction {
  static const String idle = 'idle';
  static const String listen = 'listen';
  static const String think = 'think';
  static const String speak = 'speak';
  static const String comfort = 'comfort';
  static const String celebrate = 'celebrate';
}

/// Decides Neura's next behavior/action based on context, memory, and emotion.
///
/// Decision priority (highest to lowest):
/// 1. Recent distress memory (< 2 h old)  → comfort
/// 2. High stress (>= 0.70)               → comfort
/// 3. User inactive                        → idle
/// 4. Positive + high arousal             → celebrate
/// 5. Recent help/question memory (< 30 m) → speak
/// 6. Moderate arousal (>= 0.4)           → listen
/// 7. Default                              → idle
class BehaviorEngine {
  final MemoryCore memoryCore;
  final EmotionCore emotionCore;

  BehaviorEngine({required this.memoryCore, required this.emotionCore});

  Future<void> init() async {
    // Reserved for future model loading or rule initialisation.
  }

  Future<BehaviorDecision> decideNext({
    required ContextSnapshot context,
  }) async {
    final emotion = emotionCore.latest;

    // 1. Safety / distress memory.
    final distressHits = memoryCore.search('unsafe danger hurt crisis');
    final recentDistress = distressHits.any(
      (n) => DateTime.now().difference(n.createdAt).inHours < 2,
    );
    if (recentDistress) {
      return const BehaviorDecision(
        action: BehaviorAction.comfort,
        params: {'trigger': 'distress_memory'},
      );
    }

    // 2. High stress.
    if (emotion != null && emotion.stress >= 0.70) {
      return BehaviorDecision(
        action: BehaviorAction.comfort,
        params: {'stress': emotion.stress},
      );
    }

    // 3. User inactive.
    if (!context.userActive) {
      return const BehaviorDecision(action: BehaviorAction.idle);
    }

    // 4. Positive + energised.
    if (emotion != null && emotion.valence >= 0.6 && emotion.arousal >= 0.6) {
      return BehaviorDecision(
        action: BehaviorAction.celebrate,
        params: {'valence': emotion.valence, 'arousal': emotion.arousal},
      );
    }

    // 5. Recent help / question memory.
    final helpHits = memoryCore.search('help question ask how why what');
    final recentHelp = helpHits.any(
      (n) => DateTime.now().difference(n.createdAt).inMinutes < 30,
    );
    if (recentHelp) {
      return const BehaviorDecision(
        action: BehaviorAction.speak,
        params: {'trigger': 'help_memory'},
      );
    }

    // 6. Moderate arousal → ready to listen.
    if (emotion != null && emotion.arousal >= 0.4) {
      return const BehaviorDecision(action: BehaviorAction.listen);
    }

    // 7. Default.
    return const BehaviorDecision(action: BehaviorAction.idle);
  }
}
