import 'dart:convert';

class WeeklySnapshotEntry {
  final DateTime date;
  final double moodScore; // 0.0 - 10.0
  final int stormsCount;
  final int ritualsCompleted;
  final bool usedCareMode;
  final String note;

  WeeklySnapshotEntry({
    required this.date,
    required this.moodScore,
    required this.stormsCount,
    required this.ritualsCompleted,
    required this.usedCareMode,
    required this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'moodScore': moodScore,
      'stormsCount': stormsCount,
      'ritualsCompleted': ritualsCompleted,
      'usedCareMode': usedCareMode,
      'note': note,
    };
  }

  factory WeeklySnapshotEntry.fromMap(Map<String, dynamic> map) {
    return WeeklySnapshotEntry(
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      moodScore: (map['moodScore'] as num?)?.toDouble() ?? 0.0,
      stormsCount: (map['stormsCount'] as num?)?.toInt() ?? 0,
      ritualsCompleted: (map['ritualsCompleted'] as num?)?.toInt() ?? 0,
      usedCareMode: map['usedCareMode'] as bool? ?? false,
      note: map['note'] as String? ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory WeeklySnapshotEntry.fromJson(String source) =>
      WeeklySnapshotEntry.fromMap(json.decode(source) as Map<String, dynamic>);
}
