import 'dart:math' as math;

import '../cognitive/neura_cognitive_state.dart';
import '../modules/mood/mood_store.dart';
import '../modules/quests/quest_models.dart';
import '../modules/quests/quest_store.dart';
import '../src/modules/focus/focus_controller.dart';
import '../src/modules/focus/focus_mode.dart';

typedef NeuraLiveSignalClock = DateTime Function();
typedef NeuraMoodScoreReader = Future<NeuraMoodScoreSignal?> Function();
typedef NeuraQuestSnapshotReader = Future<NeuraQuestSignalSnapshot> Function();
typedef NeuraFocusModeReader = FocusMode Function();

class NeuraLiveSignalSourcePolicy {
  const NeuraLiveSignalSourcePolicy({
    this.useMood = true,
    this.useFocus = true,
    this.useQuests = true,
    this.useActivity = true,
  });

  final bool useMood;
  final bool useFocus;
  final bool useQuests;
  final bool useActivity;
}

class NeuraMoodScoreSignal {
  const NeuraMoodScoreSignal({
    required this.score0to10,
    required this.observedAt,
  });

  final int score0to10;
  final DateTime observedAt;
}

class NeuraQuestSignalSnapshot {
  const NeuraQuestSignalSnapshot({
    required this.activeQuestCount,
    required this.completionsLastSevenDays,
    required this.observedAt,
  });

  final int activeQuestCount;
  final int completionsLastSevenDays;
  final DateTime observedAt;
}

class NeuraAdaptiveActivitySnapshot {
  const NeuraAdaptiveActivitySnapshot({
    required this.surfaceSwitchCount,
    required this.interruptionCount,
    required this.window,
    required this.observedAt,
  });

  final int surfaceSwitchCount;
  final int interruptionCount;
  final Duration window;
  final DateTime observedAt;

  double get taskSwitchRate =>
      (surfaceSwitchCount / 12).clamp(0.0, 1.0).toDouble();

  double get interruptionPressure =>
      (interruptionCount / 10).clamp(0.0, 1.0).toDouble();
}

class NeuraAdaptiveActivityTracker {
  NeuraAdaptiveActivityTracker._();

  static final NeuraAdaptiveActivityTracker instance =
      NeuraAdaptiveActivityTracker._();

  static const _maxEvents = 240;

  final List<DateTime> _surfaceSwitches = <DateTime>[];
  final List<DateTime> _interruptions = <DateTime>[];
  String? _lastSurface;

  void recordSurfaceVisit(String surfaceId, {DateTime? at}) {
    final normalized = surfaceId.trim();
    if (normalized.isEmpty || normalized == _lastSurface) return;
    _lastSurface = normalized;
    _surfaceSwitches.add((at ?? DateTime.now()).toUtc());
    _bound(_surfaceSwitches);
  }

  void recordInterruption({DateTime? at}) {
    _interruptions.add((at ?? DateTime.now()).toUtc());
    _bound(_interruptions);
  }

  NeuraAdaptiveActivitySnapshot snapshot({
    DateTime? now,
    Duration window = const Duration(hours: 1),
  }) {
    final observedAt = (now ?? DateTime.now()).toUtc();
    final cutoff = observedAt.subtract(window);
    _surfaceSwitches.removeWhere((item) => item.isBefore(cutoff));
    _interruptions.removeWhere((item) => item.isBefore(cutoff));
    return NeuraAdaptiveActivitySnapshot(
      surfaceSwitchCount: _surfaceSwitches.length,
      interruptionCount: _interruptions.length,
      window: window,
      observedAt: observedAt,
    );
  }

  void resetAfterDataWipe() {
    _surfaceSwitches.clear();
    _interruptions.clear();
    _lastSurface = null;
  }

  void _bound(List<DateTime> values) {
    if (values.length > _maxEvents) {
      values.removeRange(0, values.length - _maxEvents);
    }
  }
}

class NeuraLiveSignalEvidence {
  const NeuraLiveSignalEvidence({
    required this.source,
    required this.summary,
    required this.confidence,
    required this.observedAt,
    required this.validFor,
    this.selfReported = false,
  });

  final String source;
  final String summary;
  final double confidence;
  final DateTime observedAt;
  final Duration validFor;
  final bool selfReported;

  bool isFreshAt(DateTime now) =>
      now.toUtc().isBefore(observedAt.toUtc().add(validFor));
}

class NeuraLiveSignalSnapshot {
  NeuraLiveSignalSnapshot({
    required this.signals,
    required Iterable<NeuraLiveSignalEvidence> evidence,
    required Iterable<String> unavailableSources,
    required this.generatedAt,
  })  : evidence = List<NeuraLiveSignalEvidence>.unmodifiable(evidence),
        unavailableSources = List<String>.unmodifiable(unavailableSources);

  final NeuraCognitiveSignals signals;
  final List<NeuraLiveSignalEvidence> evidence;
  final List<String> unavailableSources;
  final DateTime generatedAt;
}

class NeuraLiveSignalAdapter {
  NeuraLiveSignalAdapter({
    NeuraMoodScoreReader? moodReader,
    NeuraQuestSnapshotReader? questReader,
    NeuraFocusModeReader? focusModeReader,
    NeuraAdaptiveActivityTracker? activityTracker,
    NeuraLiveSignalClock? clock,
  })  : _moodReader = moodReader ?? _readLatestMoodScore,
        _questReader = questReader ?? _readQuestSnapshot,
        _focusModeReader =
            focusModeReader ?? (() => FocusController.instance.state.value.mode),
        activityTracker =
            activityTracker ?? NeuraAdaptiveActivityTracker.instance,
        _clock = clock ?? DateTime.now;

  static final NeuraLiveSignalAdapter instance = NeuraLiveSignalAdapter();

  final NeuraMoodScoreReader _moodReader;
  final NeuraQuestSnapshotReader _questReader;
  final NeuraFocusModeReader _focusModeReader;
  final NeuraLiveSignalClock _clock;
  final NeuraAdaptiveActivityTracker activityTracker;

  Future<NeuraLiveSignalSnapshot> collect({
    required NeuraCognitiveSignals baseline,
    NeuraLiveSignalSourcePolicy policy =
        const NeuraLiveSignalSourcePolicy(),
  }) async {
    final now = _clock().toUtc();
    final evidence = <NeuraLiveSignalEvidence>[];
    final unavailable = <String>[];

    var energy = baseline.energy;
    var focus = baseline.focus;
    var cognitiveLoad = baseline.cognitiveLoad;
    var urgency = baseline.urgency;
    var taskSwitchRate = baseline.taskSwitchRate;
    var completionRate = baseline.completionRate;
    var notificationPressure = baseline.notificationPressure;
    var includesSelfReport = false;

    if (policy.useMood) {
      try {
        final mood = await _moodReader();
        if (mood != null &&
            _isFresh(
              mood.observedAt,
              now,
              const Duration(hours: 48),
            )) {
          final normalizedMood =
              (mood.score0to10 / 10).clamp(0.0, 1.0).toDouble();
          energy = _blend(energy, normalizedMood, 0.35);
          cognitiveLoad = _blend(cognitiveLoad, 1 - normalizedMood, 0.20);
          includesSelfReport = true;
          evidence.add(
            NeuraLiveSignalEvidence(
              source: 'mood_score',
              summary:
                  'A recent on-device mood score contributed to available-resource estimates.',
              confidence: 0.72,
              observedAt: mood.observedAt.toUtc(),
              validFor: const Duration(hours: 48),
              selfReported: true,
            ),
          );
        }
      } catch (_) {
        unavailable.add('mood_score');
      }
    }

    if (policy.useFocus) {
      try {
        final selectedMode = _focusModeReader();
        final modeFocus = switch (selectedMode) {
          FocusMode.deepWork => 0.90,
          FocusMode.reflection => 0.64,
          FocusMode.social => 0.58,
          FocusMode.windDown => 0.34,
          FocusMode.off => 0.50,
        };
        focus = _blend(focus, modeFocus, 0.65);
        if (selectedMode == FocusMode.windDown) {
          cognitiveLoad = _blend(cognitiveLoad, 0.55, 0.12);
        }
        evidence.add(
          NeuraLiveSignalEvidence(
            source: 'focus_mode',
            summary:
                'The user-selected Focus Mode contributed to attention estimates.',
            confidence: 0.88,
            observedAt: now,
            validFor: const Duration(hours: 4),
          ),
        );
      } catch (_) {
        unavailable.add('focus_mode');
      }
    }

    if (policy.useQuests) {
      try {
        final quests = await _questReader();
        final active = math.max(0, quests.activeQuestCount);
        final recentDone = math.max(0, quests.completionsLastSevenDays);
        final denominator = math.max(1, active + recentDone);
        final recentCompletion =
            (recentDone / denominator).clamp(0.0, 1.0).toDouble();
        final activePressure = (active / 12).clamp(0.0, 1.0).toDouble();

        completionRate = _blend(completionRate, recentCompletion, 0.55);
        cognitiveLoad = _blend(cognitiveLoad, activePressure, 0.15);
        urgency = _blend(
          urgency,
          (active / 10).clamp(0.0, 1.0).toDouble(),
          0.20,
        );
        evidence.add(
          NeuraLiveSignalEvidence(
            source: 'quest_momentum',
            summary:
                'Only quest counts and recent completion counts were used.',
            confidence: 0.78,
            observedAt: quests.observedAt.toUtc(),
            validFor: const Duration(hours: 6),
          ),
        );
      } catch (_) {
        unavailable.add('quest_momentum');
      }
    }

    if (policy.useActivity) {
      try {
        final activity = activityTracker.snapshot(now: now);
        taskSwitchRate = _blend(
          taskSwitchRate,
          activity.taskSwitchRate,
          0.65,
        );
        notificationPressure = _blend(
          notificationPressure,
          activity.interruptionPressure,
          0.60,
        );
        cognitiveLoad = _blend(
          cognitiveLoad,
          math.max(
            activity.taskSwitchRate,
            activity.interruptionPressure,
          ),
          0.18,
        );
        evidence.add(
          NeuraLiveSignalEvidence(
            source: 'in_app_activity',
            summary:
                'Only in-app surface-switch and interruption counts were used.',
            confidence: 0.70,
            observedAt: activity.observedAt,
            validFor: activity.window,
          ),
        );
      } catch (_) {
        unavailable.add('in_app_activity');
      }
    }

    return NeuraLiveSignalSnapshot(
      signals: NeuraCognitiveSignals(
        energy: energy,
        focus: focus,
        cognitiveLoad: cognitiveLoad,
        urgency: urgency,
        taskSwitchRate: taskSwitchRate,
        completionRate: completionRate,
        notificationPressure: notificationPressure,
        evidenceCount: evidence.length,
        includesSelfReport: includesSelfReport,
      ).normalized(),
      evidence: evidence,
      unavailableSources: unavailable,
      generatedAt: now,
    );
  }

  static Future<NeuraMoodScoreSignal?> _readLatestMoodScore() async {
    final latest = await MoodStore.instance.latest();
    if (latest == null) return null;
    return NeuraMoodScoreSignal(
      score0to10: latest.mood0to10,
      observedAt: latest.timestamp,
    );
  }

  static Future<NeuraQuestSignalSnapshot> _readQuestSnapshot() async {
    final quests = await QuestStore.instance.getQuests();
    final done = await QuestStore.instance.getDone();
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7));
    final active = quests.where((quest) => !quest.archived).length;
    final recentDone =
        done.where((item) => !item.day.isBefore(cutoff)).length;
    return NeuraQuestSignalSnapshot(
      activeQuestCount: active,
      completionsLastSevenDays: recentDone,
      observedAt: now,
    );
  }

  bool _isFresh(DateTime observedAt, DateTime now, Duration validFor) {
    final utcObserved = observedAt.toUtc();
    if (utcObserved.isAfter(now.add(const Duration(minutes: 5)))) {
      return false;
    }
    return now.difference(utcObserved) <= validFor;
  }

  double _blend(double existing, double incoming, double weight) {
    final safeExisting = existing.clamp(0.0, 1.0).toDouble();
    final safeIncoming = incoming.clamp(0.0, 1.0).toDouble();
    final safeWeight = weight.clamp(0.0, 1.0).toDouble();
    return (safeExisting * (1 - safeWeight) + safeIncoming * safeWeight)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}
