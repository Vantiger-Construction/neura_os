import 'behavior_decision.dart';
import 'context_snapshot.dart';
import 'suppression_rules.dart';
import 'action_registry.dart';

/// Decides Neura's next behavior/action based on context.
class BehaviorEngine {
  final ActionRegistry registry = ActionRegistry();
  final SuppressionRules suppression = SuppressionRules();

  BehaviorEngine();

  /// Named constructor that accepts memory/emotion cores for compatibility
  /// with NeuraSystem initialization.
  BehaviorEngine.withCores(
      {required dynamic memoryCore, required dynamic emotionCore});

  Future<void> init() async {
    // Reserved for model loading or rule initialization.
  }

  Future<BehaviorDecision> decideNext({
    required ContextSnapshot context,
  }) async {
    if (suppression.shouldSuppress('prompt', context)) {
      return const BehaviorDecision(action: 'idle');
    }
    return const BehaviorDecision(action: 'idle');
  }
}
