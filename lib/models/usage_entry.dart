class UsageEntry {
  final String id;
  final DateTime timestamp;
  final String type;
  final String source;
  final String? moodTag;

  UsageEntry({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.source,
    this.moodTag,
  });

  // Optional: Add methods for serialization if needed (e.g., to/from JSON)
  factory UsageEntry.fromJson(Map<String, dynamic> json) {
    return UsageEntry(
      id: (json['id'] ?? '').toString(),
      timestamp: DateTime.parse(json['timestamp'].toString()),
      type: (json['type'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      moodTag: json['moodTag']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'source': source,
      'moodTag': moodTag,
    };
  }
}
