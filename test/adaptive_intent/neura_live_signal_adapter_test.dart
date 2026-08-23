import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_live_signal_adapter.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';
import 'package:neuro_companion/src/modules/focus/focus_mode.dart';

void main() {
  final tracker = NeuraAdaptiveActivityTracker.instance;

  setUp(tracker.resetAfterDataWipe);
  tearDown(tracker.resetAfterDataWipe);

  test('adapter fuses only normalized local values and event counts', () async {
    final now = DateTime.utc(2026, 8, 23, 12);
    tracker.recordSurfaceVisit(
      'home',
      at: now.subtract(const Duration(minutes: 5)),
    );
    tracker.recordSurfaceVisit(
      'journal',
      at: now.subtract(const Duration(minutes: 4)),
    );
    tracker.recordSurfaceVisit(
      'quests',
      at: now.subtract(const Duration(minutes: 3)),
    );
    tracker.recordInterruption(
      at: now.subtract(const Duration(minutes: 2)),
    );
    tracker.recordInterruption(
      at: now.subtract(const Duration(minutes: 1)),
    );

    final adapter = NeuraLiveSignalAdapter(
      moodReader: () async => NeuraMoodScoreSignal(
        score0to10: 3,
        observedAt: now.subtract(const Duration(hours: 2)),
      ),
      questReader: () async => NeuraQuestSignalSnapshot(
        activeQuestCount: 6,
        completionsLastSevenDays: 2,
        observedAt: now,
      ),
      focusModeReader: () => FocusMode.deepWork,
      activityTracker: tracker,
      clock: () => now,
    );

    final snapshot = await adapter.collect(
      baseline: NeuraCognitiveSignals.defaults(),
    );

    expect(
      snapshot.evidence.map((item) => item.source),
      containsAll(<String>[
        'mood_score',
        'focus_mode',
        'quest_momentum',
        'in_app_activity',
      ]),
    );
    expect(snapshot.signals.includesSelfReport, isTrue);
    expect(snapshot.signals.evidenceCount, 4);
    expect(snapshot.signals.focus, greaterThan(0.70));
    expect(snapshot.signals.taskSwitchRate, greaterThan(0));
    expect(snapshot.signals.notificationPressure, greaterThan(0));
    expect(snapshot.signals.completionRate, lessThan(0.55));

    final serializedEvidence = snapshot.evidence
        .map((item) => '${item.source}:${item.summary}')
        .join('|');
    expect(serializedEvidence, isNot(contains('private note')));
  });

  test('disabled sources are not read', () async {
    var moodReads = 0;
    var questReads = 0;
    final adapter = NeuraLiveSignalAdapter(
      moodReader: () async {
        moodReads += 1;
        return null;
      },
      questReader: () async {
        questReads += 1;
        return NeuraQuestSignalSnapshot(
          activeQuestCount: 0,
          completionsLastSevenDays: 0,
          observedAt: DateTime.utc(2026, 8, 23),
        );
      },
      focusModeReader: () => FocusMode.off,
      activityTracker: tracker,
      clock: () => DateTime.utc(2026, 8, 23),
    );

    final snapshot = await adapter.collect(
      baseline: NeuraCognitiveSignals.defaults(),
      policy: const NeuraLiveSignalSourcePolicy(
        useMood: false,
        useFocus: false,
        useQuests: false,
        useActivity: false,
      ),
    );

    expect(moodReads, 0);
    expect(questReads, 0);
    expect(snapshot.evidence, isEmpty);
    expect(snapshot.signals.evidenceCount, 0);
  });
}
