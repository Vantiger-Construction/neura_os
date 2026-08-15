import 'dart:convert';

class Quest {
  final String id;
  final String title;
  final String details;
  final DateTime createdAt;
  final bool archived;

  const Quest({
    required this.id,
    required this.title,
    required this.details,
    required this.createdAt,
    this.archived = false,
  });

  Quest copyWith({
    String? id,
    String? title,
    String? details,
    DateTime? createdAt,
    bool? archived,
  }) {
    return Quest(
      id: id ?? this.id,
      title: title ?? this.title,
      details: details ?? this.details,
      createdAt: createdAt ?? this.createdAt,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'details': details,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'archived': archived,
      };

  static Quest fromJson(Map<String, dynamic> j) => Quest(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        details: j['details']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
        archived: (j['archived'] as bool?) ?? false,
      );
}

class QuestDone {
  final String questId;
  final DateTime day; // normalized to local midnight

  const QuestDone({required this.questId, required this.day});

  Map<String, dynamic> toJson() => {
        'questId': questId,
        'day': day.toIso8601String(),
      };

  static QuestDone fromJson(Map<String, dynamic> j) => QuestDone(
        questId: j['questId']?.toString() ?? '',
        day: DateTime.tryParse(j['day']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

DateTime normalizeDay(DateTime d) => DateTime(d.year, d.month, d.day);

String encodeQuestList(List<Quest> list) =>
    jsonEncode(list.map((e) => e.toJson()).toList());

List<Quest> decodeQuestList(String raw) {
  if (raw.trim().isEmpty) return <Quest>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Quest>[];
    final out = decoded
        .whereType<Map>()
        .map((m) => Quest.fromJson(m.cast<String, dynamic>()))
        .toList();
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  } catch (_) {
    return <Quest>[];
  }
}

String encodeDoneList(List<QuestDone> list) =>
    jsonEncode(list.map((e) => e.toJson()).toList());

List<QuestDone> decodeDoneList(String raw) {
  if (raw.trim().isEmpty) return <QuestDone>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <QuestDone>[];
    final out = decoded
        .whereType<Map>()
        .map((m) => QuestDone.fromJson(m.cast<String, dynamic>()))
        .toList();
    out.sort((a, b) => a.day.compareTo(b.day));
    return out;
  } catch (_) {
    return <QuestDone>[];
  }
}
