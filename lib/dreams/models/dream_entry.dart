import 'dart:convert';

class DreamEntry {
  final String id;
  final DateTime date;
  final String title;
  final String description;
  final List<String> tags;
  final int vividness;
  final String mood;

  /// Legacy fields kept for backward compatibility with DreamShow2Screen.
  String get text => description;
  List<String> get themes => tags;

  DreamEntry({
    String? id,
    required this.date,
    this.title = '',
    this.description = '',
    List<String>? tags,
    this.vividness = 3,
    this.mood = 'weird',
    // Legacy named params so old call sites still compile.
    String? text,
    List<String>? themes,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        tags = tags ?? themes ?? const [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'title': title,
      'description': description,
      'tags': tags,
      'vividness': vividness,
      'mood': mood,
    };
  }

  factory DreamEntry.fromMap(Map<String, dynamic> map) {
    return DreamEntry(
      id: map['id'] as String?,
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      title: map['title'] as String? ?? '',
      description:
          map['description'] as String? ?? map['text'] as String? ?? '',
      tags: (map['tags'] as List?)?.whereType<String>().toList() ??
          (map['themes'] as List?)?.whereType<String>().toList() ??
          const [],
      vividness: (map['vividness'] as num?)?.toInt() ?? 3,
      mood: map['mood'] as String? ?? 'weird',
    );
  }

  String toJson() => json.encode(toMap());

  factory DreamEntry.fromJson(String source) =>
      DreamEntry.fromMap(json.decode(source) as Map<String, dynamic>);
}
