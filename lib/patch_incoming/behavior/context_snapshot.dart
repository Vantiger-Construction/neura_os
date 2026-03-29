/// A snapshot of the current context for the behavior engine.
class ContextSnapshot {
  final DateTime now;
  final String location;
  final bool userActive;

  const ContextSnapshot({
    required this.now,
    required this.location,
    required this.userActive,
  });
}
