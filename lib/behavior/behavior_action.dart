/// Represents an action that Neura can take
class BehaviorAction {
  final String name;
  final String description;
  final Function execute;
  
  BehaviorAction({
    required this.name,
    required this.description,
    required this.execute,
  });
}
