/// Represents a decision made by the behavior engine
class BehaviorDecision {
  final String action;
  final double confidence;
  final String reasoning;
  
  BehaviorDecision({
    required this.action,
    required this.confidence,
    required this.reasoning,
  });
}
