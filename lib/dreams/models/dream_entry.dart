import 'dart:convert';

class DreamEntry {
  final DateTime date;
  final String text;
  final List<String> themes;

  DreamEntry({
    required this.date,
    required this.text,
    required this.themes,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'text': text,
      'themes': themes,
    };
  }

  factory DreamEntry.fromMap(Map<String, dynamic> map) {
    return DreamEntry(
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      text: map['text'] as String? ?? '',
      themes: (map['themes'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  String toJson() => json.encode(toMap());

  factory DreamEntry.fromJson(String source) =>
      DreamEntry.fromMap(json.decode(source) as Map<String, dynamic>);
}
