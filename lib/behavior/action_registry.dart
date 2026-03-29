import 'behavior_action.dart';

/// Registry of available actions the behavior engine can dispatch.
class ActionRegistry {
  final Map<String, BehaviorAction> _actions = {};

  void register(BehaviorAction action) {
    _actions[action.id] = action;
  }

  BehaviorAction? lookup(String id) => _actions[id];

  List<BehaviorAction> get all => _actions.values.toList();
}
