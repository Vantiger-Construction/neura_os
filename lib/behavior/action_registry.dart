/// Registry for behavior actions that Neura can perform
class ActionRegistry {
  final Map<String, Function> _actions = {};
  
  void registerAction(String name, Function action) {
    _actions[name] = action;
  }
  
  Function? getAction(String name) {
    return _actions[name];
  }
  
  List<String> listActions() {
    return _actions.keys.toList();
  }
}
