enum NeuraContentType {
  ritual,
  miniLesson,
  reflectionPrompt,
  microQuest,
  joyMoment,
}

class NeuraContentItem {
  final String id;
  final NeuraContentType type;
  final String title;
  final String body;
  final List<String> actions;
  final Map<String, dynamic> meta;

  const NeuraContentItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.actions = const [],
    this.meta = const {},
  });

  NeuraContentItem copyWith({
    String? id,
    NeuraContentType? type,
    String? title,
    String? body,
    List<String>? actions,
    Map<String, dynamic>? meta,
  }) {
    return NeuraContentItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      actions: actions ?? this.actions,
      meta: meta ?? this.meta,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'actions': actions,
        'meta': meta,
      };

  static NeuraContentItem fromJson(Map<String, dynamic> json) {
    final typeName = (json['type'] ?? 'reflectionPrompt').toString();
    final type = NeuraContentType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => NeuraContentType.reflectionPrompt,
    );
    return NeuraContentItem(
      id: (json['id'] ?? '').toString(),
      type: type,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      actions: (json['actions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      meta: (json['meta'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? const {},
    );
  }
}
