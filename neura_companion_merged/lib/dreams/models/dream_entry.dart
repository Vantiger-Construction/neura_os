class DreamEntry {
  final String id;
  final DateTime date;
  final String title;
  final String description;
  final List<String> themes;
  final String? mood;
  final double? vividness;
  final List<String>? tags;

  DreamEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.description,
    required this.themes,
    this.mood,
    this.vividness,
    this.tags,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'title': title,
      'description': description,
      'themes': themes,
      'mood': mood,
      'vividness': vividness,
      'tags': tags,
    };
  }

  factory DreamEntry.fromMap(Map<String, dynamic> map) {
    return DreamEntry(
      id: map['id'] as String? ?? '',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      themes: (map['themes'] as List?)?.whereType<String>().toList() ?? const [],
      mood: map['mood'] as String?,
      vividness: (map['vividness'] as num?)?.toDouble(),
      tags: (map['tags'] as List?)?.whereType<String>().toList(),
    );
  }
}
