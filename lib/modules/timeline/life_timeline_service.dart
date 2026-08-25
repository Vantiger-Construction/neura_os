import '../mood/mood_store.dart';
import '../pay_it_forward/goodwill_store.dart';
import '../quests/quest_store.dart';
import '../review/weekly_review_store.dart';
import '../coach/coach_store.dart';

import 'life_event.dart';

class LifeTimelineService {
  LifeTimelineService._();
  static final LifeTimelineService instance = LifeTimelineService._();

  Future<List<LifeEvent>> build({int maxItems = 500}) async {
    final results = <LifeEvent>[];

    final moodsF = MoodStore.instance.getAll();
    final kindnessF = GoodwillStore.instance.getAll();
    final questsF = QuestStore.instance.getQuests();
    final doneF = QuestStore.instance.getDone();
    final reviewsF = WeeklyReviewStore.instance.getAll();
    final coachF = CoachStore.instance.getAll();

    final moods = await moodsF;
    for (final m in moods) {
      results.add(LifeEvent(
        ts: m.timestamp,
        type: 'mood',
        title: 'Mood check-in: ${m.mood0to10}/10',
        subtitle: m.note.isEmpty ? 'No note' : m.note,
        data: {
          'mood': m.mood0to10,
          'note': m.note,
        },
      ));
    }

    final kindness = await kindnessF;
    for (final k in kindness) {
      results.add(LifeEvent(
        ts: k.timestamp,
        type: 'kindness',
        title: 'Kindness: ${k.category}',
        subtitle: k.note.isEmpty ? 'Logged a good deed' : k.note,
        data: {
          'category': k.category,
          'note': k.note,
        },
      ));
    }

    final quests = await questsF;
    final questById = {for (final q in quests) q.id: q};

    final done = await doneF;
    for (final d in done) {
      final q = questById[d.questId];
      final title = q?.title.trim().isNotEmpty == true ? q!.title : d.questId;
      results.add(LifeEvent(
        ts: d.day.add(const Duration(hours: 12)),
        type: 'quest',
        title: 'Quest done: $title',
        subtitle:
            q?.details.trim().isNotEmpty == true ? q!.details : 'Completed',
        data: {
          'questId': d.questId,
          'questTitle': q?.title ?? '',
        },
      ));
    }

    final reviews = await reviewsF;
    for (final r in reviews) {
      results.add(LifeEvent(
        ts: r.weekStart.add(const Duration(days: 6, hours: 18)),
        type: 'review',
        title: 'Weekly review (${r.weekStart.month}/${r.weekStart.day})',
        subtitle:
            'Mood avg ${r.moodAvg}/10 • Kindness ${r.kindnessActs} • Quests ${r.questDone}',
        data: {
          'weekStart': r.weekStart.toIso8601String(),
          'moodAvg': r.moodAvg,
          'moodMin': r.moodMin,
          'moodMax': r.moodMax,
          'moodSamples': r.moodSamples,
          'kindnessActs': r.kindnessActs,
          'questDone': r.questDone,
          'topLearned': r.topLearned,
          'note': r.note,
        },
      ));
    }

    final coach = await coachF;
    for (final c in coach) {
      results.add(LifeEvent(
        ts: c.createdAt,
        type: 'coach',
        title: c.title.isEmpty ? 'Coach note' : c.title,
        subtitle: c.body.isEmpty ? '(empty)' : c.body,
        data: {
          'id': c.id,
          'source': c.source.name,
          'tags': c.tags,
        },
      ));
    }

    results.sort((a, b) => b.ts.compareTo(a.ts));
    if (results.length > maxItems) {
      return results.sublist(0, maxItems);
    }
    return results;
  }
}
