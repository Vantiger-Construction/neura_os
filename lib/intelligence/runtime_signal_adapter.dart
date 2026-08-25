import '../modules/human/human_prefs_controller.dart';
import '../modules/mood/mood_store.dart';
import '../modules/quests/quest_models.dart';
import '../modules/quests/quest_store.dart';
import '../src/modules/focus/focus_controller.dart';
import 'models.dart';
import 'signal_graph.dart';

/// Converts Neura's existing local stores into a privacy-labelled snapshot.
///
/// Missing health or wearable signals are omitted rather than represented as
/// zero. Raw notes, journal text, therapy text, and memory content are never
/// read by this adapter.
class NeuraRuntimeSignalAdapter {
  const NeuraRuntimeSignalAdapter({
    this.signalGraph = const NeuraSignalGraph(),
  });

  final NeuraSignalGraph signalGraph;

  Future<NeuraIntelligenceSnapshot> snapshot({
    DateTime? now,
    bool allowSensitiveSignals = false,
  }) async {
    final generatedAt = now ?? DateTime.now();
    final observations = <NeuraSignalObservation>[];

    await _addMoodObservations(observations);
    await _addQuestObservations(observations, generatedAt);
    _addGoalObservations(observations, generatedAt);
    _addFocusObservation(observations);

    return signalGraph.fuse(
      observations: observations,
      now: generatedAt,
      allowSensitiveSignals: allowSensitiveSignals,
    );
  }

  Future<void> _addMoodObservations(
    List<NeuraSignalObservation> observations,
  ) async {
    final moods = await MoodStore.instance.getAll();
    final start = moods.length > 3 ? moods.length - 3 : 0;
    for (var index = start; index < moods.length; index++) {
      final mood = moods[index];
      observations.add(
        NeuraSignalObservation(
          id: 'mood:${mood.timestamp.toUtc().toIso8601String()}',
          kind: NeuraSignalKind.mood,
          source: 'mood_store',
          summary: 'Recent numeric mood check-in',
          observedAt: mood.timestamp,
          numericValue: mood.mood0to10 / 10,
          confidence: index == moods.length - 1 ? 0.95 : 0.72,
          sensitivity: NeuraSensitivity.personal,
          validFor: const Duration(days: 3),
        ),
      );
    }
  }

  Future<void> _addQuestObservations(
    List<NeuraSignalObservation> observations,
    DateTime now,
  ) async {
    final quests = await QuestStore.instance.getQuests();
    final active = quests.where((quest) => !quest.archived).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (active.isEmpty) return;

    final done = await QuestStore.instance.getDone();
    final today = normalizeDay(now);
    Quest? current;
    for (final quest in active) {
      final doneToday = done.any(
        (item) => item.questId == quest.id && normalizeDay(item.day) == today,
      );
      if (!doneToday) {
        current = quest;
        break;
      }
    }
    final selected = current ?? active.first;

    var mostRecentActivity = selected.createdAt;
    for (final item in done) {
      if (item.questId == selected.id && item.day.isAfter(mostRecentActivity)) {
        mostRecentActivity = item.day;
      }
    }
    observations.add(
      NeuraSignalObservation(
        id: 'quest:${selected.id}',
        kind: NeuraSignalKind.activeQuest,
        source: 'quest_store',
        summary: 'An active local quest is available',
        observedAt: mostRecentActivity,
        numericValue: 1,
        label: selected.title,
        confidence: 0.9,
        sensitivity: NeuraSensitivity.personal,
        validFor: const Duration(days: 30),
      ),
    );

    final cutoff = now.subtract(const Duration(days: 7));
    final recentDays = done
        .where((item) => item.day.isAfter(cutoff))
        .map((item) => normalizeDay(item.day))
        .toSet();
    final observedAt = recentDays.isEmpty
        ? mostRecentActivity
        : recentDays.reduce((a, b) => a.isAfter(b) ? a : b);
    observations.add(
      NeuraSignalObservation(
        id: 'quest_momentum:${selected.id}:${normalizeDay(now).toIso8601String()}',
        kind: NeuraSignalKind.questMomentum,
        source: 'quest_store',
        summary: 'Seven-day quest completion momentum',
        observedAt: observedAt,
        numericValue: recentDays.length / 7,
        confidence: 0.86,
        sensitivity: NeuraSensitivity.personal,
        validFor: const Duration(days: 14),
      ),
    );
  }

  void _addGoalObservations(
    List<NeuraSignalObservation> observations,
    DateTime now,
  ) {
    final goals = HumanPrefsController.instance.prefs.value.persona.goals;
    final weekBucket =
        now.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay ~/ 7;
    for (var index = 0; index < goals.length && index < 3; index++) {
      final goal = goals[index].trim();
      if (goal.isEmpty) continue;
      observations.add(
        NeuraSignalObservation(
          id: 'persona_goal:$index:$weekBucket',
          kind: NeuraSignalKind.goal,
          source: 'human_preferences',
          summary: 'User-authored goal preference',
          observedAt: now,
          numericValue: 1,
          label: goal,
          confidence: 1,
          sensitivity: NeuraSensitivity.personal,
          validFor: const Duration(days: 180),
        ),
      );
    }
  }

  void _addFocusObservation(List<NeuraSignalObservation> observations) {
    final state = FocusController.instance.state.value;
    final value = switch (state.mode.name) {
      'deepWork' => 1.0,
      'windDown' => 0.85,
      'reflection' => 0.65,
      'social' => 0.6,
      _ => 0.5,
    };
    observations.add(
      NeuraSignalObservation(
        id: 'focus:${state.startedAt.toUtc().toIso8601String()}',
        kind: NeuraSignalKind.focus,
        source: 'focus_controller',
        summary: 'Current user-selected focus mode',
        observedAt: state.startedAt,
        numericValue: value,
        label: state.mode.name,
        confidence: 1,
        validFor: const Duration(days: 30),
      ),
    );
  }
}
