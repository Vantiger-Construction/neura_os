/// A decision produced by the behavior engine.
class BehaviorDecision {
  final String action;
  final Map<String, dynamic> params;

  const BehaviorDecision({required this.action, this.params = const {}});

  @override
  String toString() => 'BehaviorDecision(action: $action, params: $params)';
}
