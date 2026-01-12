/// Snapshot of the current context for behavior decision-making
class ContextSnapshot {
  final DateTime timestamp;
  final Map<String, dynamic> data;
  
  ContextSnapshot({
    required this.timestamp,
    required this.data,
  });
  
  factory ContextSnapshot.now() {
    return ContextSnapshot(
      timestamp: DateTime.now(),
      data: {},
    );
  }
}
