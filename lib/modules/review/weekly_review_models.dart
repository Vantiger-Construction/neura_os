import 'dart:convert';

class WeeklyReview {
  final DateTime weekStart; // local date
  final int moodAvg;
  final int moodMin;
  final int moodMax;
  final int moodSamples;
  final int kindnessActs;
  final int questDone;
  final List<String> topLearned; // ids of helpful actions
  final String note; // optional user note

  const WeeklyReview({
    required this.weekStart,
    required this.moodAvg,
    required this.moodMin,
    required this.moodMax,
    required this.moodSamples,
    required this.kindnessActs,
    required this.questDone,
    required this.topLearned,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'weekStart': weekStart.toIso8601String(),
        'moodAvg': moodAvg,
        'moodMin': moodMin,
        'moodMax': moodMax,
        'moodSamples': moodSamples,
        'kindnessActs': kindnessActs,
        'questDone': questDone,
        'topLearned': topLearned,
        'note': note,
      };

  static WeeklyReview fromJson(Map<String, dynamic> j) => WeeklyReview(
        weekStart: DateTime.tryParse(j['weekStart']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        moodAvg: (j['moodAvg'] as num?)?.round() ?? 0,
        moodMin: (j['moodMin'] as num?)?.round() ?? 0,
        moodMax: (j['moodMax'] as num?)?.round() ?? 0,
        moodSamples: (j['moodSamples'] as num?)?.round() ?? 0,
        kindnessActs: (j['kindnessActs'] as num?)?.round() ?? 0,
        questDone: (j['questDone'] as num?)?.round() ?? 0,
        topLearned: (j['topLearned'] is List)
            ? (j['topLearned'] as List).map((e) => e.toString()).toList(growable: false)
            : const <String>[],
        note: j['note']?.toString() ?? '',
      );
}

String encodeWeeklyReviews(List<WeeklyReview> list) => jsonEncode(list.map((e) => e.toJson()).toList());

List<WeeklyReview> decodeWeeklyReviews(String raw) {
  if (raw.trim().isEmpty) return <WeeklyReview>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <WeeklyReview>[];
    final out = decoded.whereType<Map>().map((m) => WeeklyReview.fromJson(m.cast<String, dynamic>())).toList();
    out.sort((a, b) => a.weekStart.compareTo(b.weekStart));
    return out;
  } catch (_) {
    return <WeeklyReview>[];
  }
}

DateTime startOfWeek(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  // Monday as start
  final delta = (local.weekday + 6) % 7; // Mon->0
  return local.subtract(Duration(days: delta));
}
