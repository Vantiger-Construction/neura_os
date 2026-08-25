import '../human/learning_store.dart';
import '../mood/mood_store.dart';
import '../pay_it_forward/goodwill_store.dart';
import '../quests/quest_store.dart';
import 'weekly_review_models.dart';
import '../../startup/neura_prefs_cache.dart';

class WeeklyReviewStore {
  WeeklyReviewStore._();
  static final WeeklyReviewStore instance = WeeklyReviewStore._();

  static const _key = 'neura.weekly_reviews.v1';

  Future<List<WeeklyReview>> getAll() async {
    final sp = NeuraPrefsCache.prefs;
    return decodeWeeklyReviews(sp.getString(_key) ?? '');
  }

  Future<void> _write(List<WeeklyReview> list) async {
    final sp = NeuraPrefsCache.prefs;
    await sp.setString(_key, encodeWeeklyReviews(list));
  }

  Future<WeeklyReview> generate({DateTime? forDay}) async {
    final day = forDay ?? DateTime.now();
    final weekStart = startOfWeek(day);
    final weekEnd = weekStart.add(const Duration(days: 7));

    final moods = await MoodStore.instance.getAll();
    final weekMoods = moods
        .where((m) =>
            m.timestamp
                .isAfter(weekStart.subtract(const Duration(seconds: 1))) &&
            m.timestamp.isBefore(weekEnd))
        .toList();

    int moodAvg = 0;
    int moodMin = 0;
    int moodMax = 0;
    if (weekMoods.isNotEmpty) {
      moodMin =
          weekMoods.map((e) => e.mood0to10).reduce((a, b) => a < b ? a : b);
      moodMax =
          weekMoods.map((e) => e.mood0to10).reduce((a, b) => a > b ? a : b);
      final sum = weekMoods.fold<int>(0, (p, e) => p + e.mood0to10);
      moodAvg = (sum / weekMoods.length).round();
    }

    final kindness = await GoodwillStore.instance.getAll();
    final weekKindness = kindness
        .where((k) =>
            k.timestamp
                .isAfter(weekStart.subtract(const Duration(seconds: 1))) &&
            k.timestamp.isBefore(weekEnd))
        .length;

    final questDone = await QuestStore.instance.doneCountLastDays(7);

    final topLearned = (await LearningStore.instance.top(max: 3))
        .map((e) => e.key)
        .toList(growable: false);

    final review = WeeklyReview(
      weekStart: weekStart,
      moodAvg: moodAvg,
      moodMin: moodMin,
      moodMax: moodMax,
      moodSamples: weekMoods.length,
      kindnessActs: weekKindness,
      questDone: questDone,
      topLearned: topLearned,
      note: '',
    );

    final list = await getAll();
    // replace if same week
    list.removeWhere((r) => startOfWeek(r.weekStart) == weekStart);
    list.add(review);
    await _write(list);

    return review;
  }

  Future<void> updateNote(DateTime weekStart, String note) async {
    final list = await getAll();
    final idx = list
        .indexWhere((r) => startOfWeek(r.weekStart) == startOfWeek(weekStart));
    if (idx < 0) return;
    final r = list[idx];
    list[idx] = WeeklyReview(
      weekStart: r.weekStart,
      moodAvg: r.moodAvg,
      moodMin: r.moodMin,
      moodMax: r.moodMax,
      moodSamples: r.moodSamples,
      kindnessActs: r.kindnessActs,
      questDone: r.questDone,
      topLearned: r.topLearned,
      note: note,
    );
    await _write(list);
  }

  Future<void> delete(DateTime weekStart) async {
    final list = await getAll();
    list.removeWhere((r) => startOfWeek(r.weekStart) == startOfWeek(weekStart));
    await _write(list);
  }

  Future<void> wipe() async {
    final sp = NeuraPrefsCache.prefs;
    await sp.remove(_key);
  }
}
