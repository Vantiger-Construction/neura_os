import '../human/human_prefs_controller.dart';
import '../mood/mood_models.dart';
import '../review/weekly_review_models.dart';
import '../quests/quest_models.dart';

class CoachDraft {
  final String title;
  final String body;
  final List<String> tags;

  const CoachDraft({required this.title, required this.body, required this.tags});
}

class NeuraCoachEngine {
  NeuraCoachEngine._();
  static final NeuraCoachEngine instance = NeuraCoachEngine._();

  CoachDraft forQuestDone({required Quest quest, required int streak, MoodEntry? latestMood}) {
    final persona = HumanPrefsController.instance.prefs.value.persona;
    final humor = persona.humor;
    final direct = persona.directness;
    final depth = persona.depth;

    final vibe = _vibeLine(humor: humor, direct: direct);
    final moodLine = latestMood == null
        ? ''
        : 'Mood snapshot: ${latestMood.mood0to10}/10 (${_moodLabel(latestMood.mood0to10)}).';

    final streakLine = streak <= 1 ? 'Streak started. Tiny wins count.' : 'Streak: $streak days. Momentum is real.';

    final why = depth < 0.35
        ? 'One completed action reduces mental friction.'
        : 'One completed action is a vote for the person you’re becoming.';

    final title = direct > 0.7 ? 'Quest complete. Don’t overthink it.' : 'Nice. Quest complete.';

    final body = [
      vibe,
      'You finished: “${quest.title}”.',
      if (quest.details.trim().isNotEmpty) 'Details: ${quest.details.trim()}',
      streakLine,
      if (moodLine.isNotEmpty) moodLine,
      why,
      _nextNudge(humor: humor, direct: direct),
    ].where((s) => s.trim().isNotEmpty).join('\n');

    return CoachDraft(title: title, body: body, tags: ['quest', 'streak']);
  }

  CoachDraft forWeeklyReview({required WeeklyReview review}) {
    final persona = HumanPrefsController.instance.prefs.value.persona;
    final humor = persona.humor;
    final direct = persona.directness;
    final depth = persona.depth;

    final title = 'Weekly Review: ${review.weekStart.month}/${review.weekStart.day}';

    final mood = review.moodSamples == 0
        ? 'Mood: no check-ins logged.'
        : 'Mood avg: ${review.moodAvg}/10 (range ${review.moodMin}–${review.moodMax}, ${review.moodSamples} samples).';

    final kindness = 'Kindness: ${review.kindnessActs} act${review.kindnessActs == 1 ? '' : 's'} logged.';
    final quests = 'Quest momentum: ${review.questDone} completed.';

    final learned = review.topLearned.isEmpty ? '' : 'Helpful actions: ${review.topLearned.take(3).join(', ')}.';

    final vibe = _vibeLine(humor: humor, direct: direct);

    final reflection = depth < 0.35
        ? 'Pick 1 thing to repeat next week.'
        : 'Pick 1 pattern to reinforce next week, and 1 friction to reduce.';

    final poke = humor > 0.6 ? 'Your brain is basically a raccoon: it likes shiny rewards. Give it one.' : '';

    final body = [
      vibe,
      mood,
      kindness,
      quests,
      if (learned.isNotEmpty) learned,
      if (review.note.trim().isNotEmpty) 'Your note: ${review.note.trim()}',
      reflection,
      if (poke.isNotEmpty) poke,
      _nextNudge(humor: humor, direct: direct),
    ].where((s) => s.trim().isNotEmpty).join('\n');

    return CoachDraft(title: title, body: body, tags: ['weekly', 'review']);
  }

  CoachDraft forMoodCheckin({required MoodEntry entry}) {
    final persona = HumanPrefsController.instance.prefs.value.persona;
    final humor = persona.humor;
    final direct = persona.directness;
    final depth = persona.depth;

    final vibe = _vibeLine(humor: humor, direct: direct);
    final label = _moodLabel(entry.mood0to10);

    final noteLine = entry.note.trim().isEmpty ? '' : 'Note: ${entry.note.trim()}';

    final meaning = depth < 0.35
        ? 'Log it. Move on. Consistency beats intensity.'
        : 'The point isn’t a “good mood.” It’s pattern awareness + gentle steering.';

    final title = direct > 0.7 ? 'Mood logged. Keep moving.' : 'Mood check‑in saved.';

    final body = [
      vibe,
      'Today: ${entry.mood0to10}/10 ($label).',
      if (noteLine.isNotEmpty) noteLine,
      meaning,
      _nextNudge(humor: humor, direct: direct),
    ].where((s) => s.trim().isNotEmpty).join('\n');

    return CoachDraft(title: title, body: body, tags: ['mood', label.toLowerCase()]);
  }

  CoachDraft forRescueCompleted({MoodEntry? latestMood}) {
    final persona = HumanPrefsController.instance.prefs.value.persona;
    final humor = persona.humor;
    final direct = persona.directness;

    final vibe = _vibeLine(humor: humor, direct: direct);
    final moodLine = latestMood == null
        ? ''
        : 'Latest mood: ${latestMood.mood0to10}/10 (${_moodLabel(latestMood.mood0to10)}).';

    final title = direct > 0.7 ? 'Rescue complete. Good.' : 'Two‑Minute Rescue complete.';

    final body = [
      vibe,
      'Two minutes done. That counts.',
      if (moodLine.isNotEmpty) moodLine,
      humor > 0.6 ? 'Your nervous system just got a tiny firmware update.' : 'Small resets change trajectories.',
      _nextNudge(humor: humor, direct: direct),
    ].where((s) => s.trim().isNotEmpty).join('\n');

    return CoachDraft(title: title, body: body, tags: ['rescue', 'reset']);
  }

  CoachDraft forRescueHelpful({required String actionId, MoodEntry? latestMood}) {
    final persona = HumanPrefsController.instance.prefs.value.persona;
    final humor = persona.humor;
    final direct = persona.directness;

    final vibe = _vibeLine(humor: humor, direct: direct);
    final moodLine = latestMood == null
        ? ''
        : 'Latest mood: ${latestMood.mood0to10}/10 (${_moodLabel(latestMood.mood0to10)}).';

    final title = direct > 0.7 ? 'Noted. That worked.' : 'Helpful action saved.';

    final body = [
      vibe,
      'You marked this helpful: $actionId',
      if (moodLine.isNotEmpty) moodLine,
      humor > 0.6 ? 'We shall feed this fact to the gremlins that run habits.' : 'I’ll suggest this again when it fits.',
    ].where((s) => s.trim().isNotEmpty).join('\n');

    return CoachDraft(title: title, body: body, tags: ['rescue', 'learned']);
  }

  String _vibeLine({required double humor, required double direct}) {
    if (humor > 0.75 && direct > 0.65) return 'Neura says: Nice. Keep going, you magnificent chaos wizard.';
    if (humor > 0.75) return 'Neura says: Proud of you. Also, your future self just high-fived you.';
    if (direct > 0.7) return 'Neura says: Good. Do that again tomorrow.';
    return 'Neura says: Well done. Small actions build big lives.';
  }

  String _nextNudge({required double humor, required double direct}) {
    if (direct > 0.75) return 'Next: choose one tiny follow-up. Then stop.';
    if (humor > 0.6) return 'Next: one tiny follow-up. Then go be a human in the real world.';
    return 'Next: choose one tiny follow-up action.';
  }

  String _moodLabel(int score0to10) {
    final s = score0to10.clamp(0, 10);
    if (s <= 1) return 'Rough';
    if (s <= 3) return 'Low';
    if (s <= 5) return 'Neutral';
    if (s <= 7) return 'Okay';
    if (s <= 9) return 'Good';
    return 'Excellent';
  }
}
