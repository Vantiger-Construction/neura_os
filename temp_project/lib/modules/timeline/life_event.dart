import 'dart:convert';

class LifeEvent {
  final DateTime ts;
  final String type; // mood, quest, kindness, review, coach
  final String title;
  final String subtitle;
  final Map<String, Object?> data;

  const LifeEvent({
    required this.ts,
    required this.type,
    required this.title,
    required this.subtitle,
    this.data = const {},
  });

  Map<String, Object?> toJson() => {
        'ts': ts.toUtc().toIso8601String(),
        'type': type,
        'title': title,
        'subtitle': subtitle,
        'data': data,
      };

  static String encodeList(List<LifeEvent> list) => jsonEncode(list.map((e) => e.toJson()).toList(growable: false));
}
