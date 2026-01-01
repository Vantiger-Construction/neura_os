import 'dart:convert';

enum CoachSourceType {
  questDone,
  weeklyReview,
  moodCheckin,
  rescue,
}

class CoachNote {
  final String id;
  final DateTime createdAt;
  final CoachSourceType source;
  final String title;
  final String body;
  final List<String> tags;

  const CoachNote({
    required this.id,
    required this.createdAt,
    required this.source,
    required this.title,
    required this.body,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'source': source.name,
        'title': title,
        'body': body,
        'tags': tags,
      };

  static CoachNote fromJson(Map<String, dynamic> json) {
    final srcRaw = (json['source'] as String?) ?? CoachSourceType.weeklyReview.name;
    final src = CoachSourceType.values.firstWhere(
      (e) => e.name == srcRaw,
      orElse: () => CoachSourceType.weeklyReview,
    );

    final createdRaw = json['createdAt'] as String?;
    DateTime createdAt;
    try {
      createdAt = createdRaw == null ? DateTime.now() : DateTime.parse(createdRaw);
    } catch (_) {
      createdAt = DateTime.now();
    }

    final tagsRaw = json['tags'];
    final tags = <String>[];
    if (tagsRaw is List) {
      for (final t in tagsRaw) {
        final s = t.toString().trim();
        if (s.isNotEmpty) tags.add(s);
      }
    }

    return CoachNote(
      id: (json['id'] as String?) ?? 'c_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: createdAt,
      source: src,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      tags: tags,
    );
  }
}

List<CoachNote> decodeCoachNotes(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.whereType<Map>().map((m) => CoachNote.fromJson(m.cast<String, dynamic>())).toList();
    }
  } catch (_) {}
  return <CoachNote>[];
}

String encodeCoachNotes(List<CoachNote> notes) {
  return jsonEncode(notes.map((n) => n.toJson()).toList(growable: false));
}
