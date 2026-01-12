import 'dart:convert';

enum MoodLabel {
  veryLow,
  low,
  neutral,
  lifted,
  high,
}

class MoodState {
  final DateTime date;
  /// 0.0 - 10.0
  final double score;
  final MoodLabel label;
  final String note;

  MoodState({
    required this.date,
    required this.score,
    required this.label,
    required this.note,
  });

  factory MoodState.neutral() {
    return MoodState(
      date: DateTime.now(),
      score: 5.0,
      label: MoodLabel.neutral,
      note: '',
    );
  }

  MoodState copyWith({
    DateTime? date,
    double? score,
    MoodLabel? label,
    String? note,
  }) {
    return MoodState(
      date: date ?? this.date,
      score: score ?? this.score,
      label: label ?? this.label,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'score': score,
      'label': label.toString(),
      'note': note,
    };
  }

  factory MoodState.fromMap(Map<String, dynamic> map) {
    final labelStr = map['label'] as String? ?? MoodLabel.neutral.toString();
    final label = MoodLabel.values.firstWhere(
      (m) => m.toString() == labelStr,
      orElse: () => MoodLabel.neutral,
    );
    return MoodState(
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      score: (map['score'] as num?)?.toDouble() ?? 5.0,
      label: label,
      note: map['note'] as String? ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory MoodState.fromJson(String source) =>
      MoodState.fromMap(json.decode(source) as Map<String, dynamic>);
}
