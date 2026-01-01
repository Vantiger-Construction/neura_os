import 'dart:convert';

class MoodEntry {
  final DateTime timestamp;
  final int mood0to10;
  final String note;

  MoodEntry(
      {required this.timestamp, required this.mood0to10, required this.note});

  // Getter for mood as a double value from 0.0 to 10.0
  double get mood => mood0to10.toDouble();

  Map<String, Object?> toJson() => {
        'ts': timestamp.toUtc().toIso8601String(),
        'mood': mood0to10,
        'note': note,
      };

  static MoodEntry fromJson(Map<String, Object?> json) {
    return MoodEntry(
      timestamp: DateTime.parse((json['ts'] as String)).toLocal(),
      mood0to10: (json['mood'] as num).round(),
      note: (json['note'] as String?) ?? '',
    );
  }

  static List<MoodEntry> decodeList(String raw) {
    if (raw.trim().isEmpty) return <MoodEntry>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <MoodEntry>[];
    return decoded
        .whereType<Map>()
        .map((m) => MoodEntry.fromJson(Map<String, Object?>.from(m)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  static String encodeList(List<MoodEntry> items) {
    final data = items.map((e) => e.toJson()).toList();
    return jsonEncode(data);
  }
}
