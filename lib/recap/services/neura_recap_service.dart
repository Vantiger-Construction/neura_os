import '../../core/memory/memory_graph_service.dart';
import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../../modules/review/weekly_review_models.dart';
import '../../modules/review/weekly_review_store.dart';

class RecapData {
  final DateTime from;
  final DateTime to;
  final List<MoodEntry> moodEntries;
  final int? moodAvg;
  final int? moodMin;
  final int? moodMax;
  final int kindnessActsTotal;
  final int questsDoneTotal;
  final int joyMomentsCompleted;
  final int joyMomentsSkipped;

  const RecapData({
    required this.from,
    required this.to,
    required this.moodEntries,
    required this.moodAvg,
    required this.moodMin,
    required this.moodMax,
    required this.kindnessActsTotal,
    required this.questsDoneTotal,
    required this.joyMomentsCompleted,
    required this.joyMomentsSkipped,
  });
}

/// Aggregates existing data sources (mood history, weekly reviews, joy
/// moment outcomes) into a monthly/yearly highlights recap. Read-only --
/// this never writes anything, just reads and summarizes what's already
/// tracked elsewhere.
class NeuraRecapService {
  NeuraRecapService._();
  static final NeuraRecapService instance = NeuraRecapService._();

  Future<RecapData> buildRecap(
      {required DateTime from, required DateTime to}) async {
    final allMoods = await MoodStore.instance.getAll();
    final moods = allMoods
        .where((m) => !m.timestamp.isBefore(from) && m.timestamp.isBefore(to))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    int? moodAvg;
    int? moodMin;
    int? moodMax;
    if (moods.isNotEmpty) {
      moodMin = moods.map((e) => e.mood0to10).reduce((a, b) => a < b ? a : b);
      moodMax = moods.map((e) => e.mood0to10).reduce((a, b) => a > b ? a : b);
      moodAvg = (moods.fold<int>(0, (p, e) => p + e.mood0to10) / moods.length)
          .round();
    }

    final allReviews = await WeeklyReviewStore.instance.getAll();
    final reviewsInRange = allReviews.where(
      (r) =>
          !r.weekStart
              .isBefore(_startOfWeek(from).subtract(const Duration(days: 7))) &&
          r.weekStart.isBefore(to),
    );
    final kindnessTotal =
        reviewsInRange.fold<int>(0, (p, r) => p + r.kindnessActs);
    final questsTotal = reviewsInRange.fold<int>(0, (p, r) => p + r.questDone);

    final memoryNodes =
        await MemoryGraphService.I.nodesBetween(from, to, limit: 1000);
    int joyCompleted = 0;
    int joySkipped = 0;
    for (final node in memoryNodes) {
      if (node['type'] != 'SUGGESTION:JOY_MOMENT') continue;
      final outcome = node['outcome'] as String?;
      if (outcome == 'completed') joyCompleted++;
      if (outcome == 'skipped') joySkipped++;
    }

    return RecapData(
      from: from,
      to: to,
      moodEntries: moods,
      moodAvg: moodAvg,
      moodMin: moodMin,
      moodMax: moodMax,
      kindnessActsTotal: kindnessTotal,
      questsDoneTotal: questsTotal,
      joyMomentsCompleted: joyCompleted,
      joyMomentsSkipped: joySkipped,
    );
  }

  DateTime _startOfWeek(DateTime d) => startOfWeek(d);
}
