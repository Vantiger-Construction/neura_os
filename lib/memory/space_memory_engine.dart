class SpaceMemoryEntry {
  final String roomId;
  final String mood;
  final String intent;
  final String timeOfDay;
  final double outcomeScore;
  final DateTime timestamp;

  SpaceMemoryEntry({
    required this.roomId,
    required this.mood,
    required this.intent,
    required this.timeOfDay,
    required this.outcomeScore,
    required this.timestamp,
  });
}

class SpaceMemoryEngine {
  SpaceMemoryEngine._();
  static final SpaceMemoryEngine instance = SpaceMemoryEngine._();

  final Map<String, List<SpaceMemoryEntry>> _mem = {};

  void record(SpaceMemoryEntry e) {
    final list = _mem.putIfAbsent(e.roomId, () => []);
    list.add(e);
  }

  SpaceMemoryEntry? bestFor(String roomId) {
    final list = _mem[roomId];
    if (list == null || list.isEmpty) return null;
    list.sort((a,b) => b.outcomeScore.compareTo(a.outcomeScore));
    return list.first;
  }
}
