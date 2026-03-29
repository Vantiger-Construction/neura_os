/// A concrete action Neura can take (play sound, show prompt, navigate, etc.).
class BehaviorAction {
  final String id;
  final String label;
  final void Function()? execute;

  const BehaviorAction({required this.id, required this.label, this.execute});

  @override
  String toString() => 'BehaviorAction($id)';
}
