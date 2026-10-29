import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../adaptive_intent/neura_adaptive_outcome_loop.dart';
import '../adaptive_intent/neura_live_signal_adapter.dart';
import '../adaptive_intent/neura_outcome_store.dart';
import '../after_storm/services/after_storm_service.dart';
import '../cognitive/neura_bandwidth_engine.dart';
import '../cognitive/neura_cognitive_state.dart';
import '../core/memory/memory_graph_service.dart';
import '../intelligence/capability_registry.dart';
import '../intelligence/initiative_source.dart';
import '../intelligence/intelligence_preferences.dart';
import '../intelligence/models.dart';
import '../intelligence/neura_intelligence_controller.dart';
import '../intelligence/opportunity_radar.dart';
import '../intelligence/routine_model.dart';
import '../intelligence/runtime_signal_adapter.dart';
import '../joy_engine/joy_engine.dart';
import '../joy_engine/joy_types.dart';
import '../modules/human/human_prefs_controller.dart';
import '../modules/mood/mood_store.dart';
import '../modules/quests/quest_store.dart';
import '../neura_shell/models/neura_room.dart';
import '../relationships/models/relationship_profile.dart';
import '../relationships/services/distress_detector.dart';
import '../relationships/services/relationship_insight_service.dart';
import '../relationships/services/relationship_profile_service.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';

enum ProactiveBannerKind {
  joy,
  relationship,
  quest,
  wellness,
  focus,
  care,
  dream,

  /// Routine-aware initiative with no destination, such as a welcome back.
  presence,
}

class ProactiveBanner {
  const ProactiveBanner({
    required this.kind,
    required this.title,
    required this.body,
    required this.candidate,
    required this.receipt,
    this.joyMoment,
    this.relationshipProfile,
    this.dataGeneration = 0,
    this.routineGeneration = 0,
  });

  final ProactiveBannerKind kind;
  final String title;
  final String body;
  final NeuraIntelligenceCandidate candidate;
  final NeuraDecisionReceipt receipt;
  final JoyMoment? joyMoment;
  final RelationshipProfile? relationshipProfile;
  final int dataGeneration;
  final int routineGeneration;

  bool get isInitiative => candidate.specialistId.startsWith('initiative.');
}

class _BannerCandidate {
  const _BannerCandidate({
    required this.candidate,
    required this.kind,
    this.joyMoment,
    this.relationshipProfile,
  });

  final NeuraIntelligenceCandidate candidate;
  final ProactiveBannerKind kind;
  final JoyMoment? joyMoment;
  final RelationshipProfile? relationshipProfile;

  ProactiveBanner toBanner(
    NeuraDecisionReceipt receipt,
    int generation,
    int routineGeneration,
  ) =>
      ProactiveBanner(
        kind: kind,
        title: candidate.title,
        body: candidate.body,
        candidate: candidate,
        receipt: receipt,
        joyMoment: joyMoment,
        relationshipProfile: relationshipProfile,
        dataGeneration: generation,
        routineGeneration: routineGeneration,
      );
}

/// Builds local opportunities and sends every one through Neura's privacy,
/// attention, consent, and guardrail boundary before it reaches the dashboard.
class ProactiveBannerService {
  ProactiveBannerService._() : _clock = DateTime.now {
    _listenForRoutineConsent();
  }

  @visibleForTesting
  ProactiveBannerService.forTesting({required DateTime Function() clock})
      : _clock = clock {
    _listenForRoutineConsent();
  }

  final DateTime Function() _clock;

  static final ProactiveBannerService instance = ProactiveBannerService._();

  static const _stateKey = 'neura.proactive_banner.state.v2';
  static const _extendedCooldown = Duration(days: 7);
  static const _dismissalsBeforeExtendedCooldown = 3;
  static const _stormSuppressWindow = Duration(hours: 24);

  /// Content-free app-open history for routine-aware initiative. Lives in
  /// the same prefs store the data wipe clears. A wipe cannot clear that
  /// store until every submitted banner write has actually finished.
  static const _routineKey = 'neura.initiative.routine.v1';

  final NeuraRuntimeSignalAdapter _signals = const NeuraRuntimeSignalAdapter();
  final NeuraOpportunityRadar _radar = const NeuraOpportunityRadar();
  final NeuraInitiativeSource _initiative = const NeuraInitiativeSource();
  final NeuraLiveSignalAdapter _liveSignals = NeuraLiveSignalAdapter.instance;
  final NeuraBandwidthEngine _bandwidthEngine = const NeuraBandwidthEngine();
  final NeuraOutcomeStore _outcomeStore = NeuraEncryptedOutcomeStore();
  final NeuraAdaptiveOutcomeLoop _outcomeLoop =
      const NeuraAdaptiveOutcomeLoop();
  Future<void> _writeQueue = Future<void>.value();
  bool _writesSuspended = false;
  int _dataGeneration = 0;
  int _routineGeneration = 0;
  int _pendingWrites = 0;
  bool _evaluating = false;
  bool? _routineTrackingEnabled;
  NeuraRoutineModel? _routine;
  final Map<String, ({DateTime expiresAt, String receiptId})>
      _offeredInitiatives = {};
  final Set<String> _shownReceipts = {};

  bool get _canLearnRoutine =>
      !SafeBoot.instance.safeMode.value &&
      HumanPrefsController.instance.prefs.value.allowLearning &&
      NeuraIntelligenceController
          .instance.preferences.allowsProactiveSuggestions;

  void _listenForRoutineConsent() {
    HumanPrefsController.instance.prefs.addListener(_routineConsentChanged);
    NeuraIntelligenceController.instance.addListener(_routineConsentChanged);
    SafeBoot.instance.safeMode.addListener(_routineConsentChanged);
  }

  void _routineConsentChanged() {
    final enabled = _canLearnRoutine;
    if (_routineTrackingEnabled == enabled) return;
    _routineTrackingEnabled = enabled;
    if (enabled) return;
    _routineGeneration += 1;
    _routine = NeuraRoutineModel.empty();
    _offeredInitiatives.clear();
    // Delete behind already-submitted writes, never detach their queue. A
    // later re-enable starts with an empty in-memory baseline immediately.
    unawaited(
      _enqueueWrite((_) async {
        await NeuraPrefsCache.prefs.remove(_routineKey);
      }).catchError((_) {}),
    );
  }

  @visibleForTesting
  Future<void> disposeForTesting() async {
    HumanPrefsController.instance.prefs.removeListener(_routineConsentChanged);
    NeuraIntelligenceController.instance.removeListener(_routineConsentChanged);
    SafeBoot.instance.safeMode.removeListener(_routineConsentChanged);
    await resetAfterDataWipe();
  }

  Future<Map<String, dynamic>> _loadState() async {
    try {
      final raw = NeuraPrefsCache.prefs.getString(_stateKey);
      if (raw == null || raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveState(Map<String, dynamic> state, int generation) async {
    if (!_isCurrent(generation)) return;
    await NeuraPrefsCache.prefs.setString(_stateKey, jsonEncode(state));
  }

  Future<ProactiveBanner?> maybeGetBannerOnAppOpen() async {
    // Only one caller owns a card evaluation. Other dashboard loads return
    // empty instead of sharing a Future that could display the same card twice.
    if (_evaluating || _writesSuspended || SafeBoot.instance.safeMode.value) {
      return null;
    }
    _evaluating = true;
    final generation = _dataGeneration;
    try {
      return await _evaluateAppOpen(generation);
    } finally {
      _evaluating = false;
    }
  }

  Future<ProactiveBanner?> _evaluateAppOpen(int generation) async {
    await NeuraIntelligenceController.instance.initialize();
    if (!_isCurrent(generation) || SafeBoot.instance.safeMode.value) {
      return null;
    }
    _routineConsentChanged();
    final preferences = NeuraIntelligenceController.instance.preferences;
    final now = _clock();
    _offeredInitiatives
        .removeWhere((_, offer) => !offer.expiresAt.isAfter(now));
    // Snapshot the routine *before* recording this open, so the current
    // visit is never its own precedent. Recording happens even in quiet
    // hours or cooldown, otherwise those visits would vanish from routine.
    var routine = NeuraRoutineModel.empty();
    final routineGeneration = _routineGeneration;
    if (_canLearnRoutine) {
      routine = _routine ??= _loadRoutine();
      // Advance in memory before any await. Platform persistence is optional
      // and does not hold up the banner or another app-open snapshot.
      _routine = routine.recordOpen(now);
      _persistRoutine();
    }
    if (!preferences.allowsProactiveSuggestions || preferences.isQuietAt(now)) {
      return null;
    }

    final state = await _loadState();
    final lastShownMs = _coerceInt(state['lastShownEpochMs']);
    final consecutiveDismissals =
        _coerceInt(state['consecutiveDismissals']) ?? 0;
    if (lastShownMs != null) {
      final lastShown = DateTime.fromMillisecondsSinceEpoch(lastShownMs);
      final cooldown = cooldownFor(
        preferences.proactivityLevel,
        consecutiveDismissals: consecutiveDismissals,
      );
      if (now.isBefore(lastShown.add(cooldown))) return null;
    }

    NeuraIntelligenceSnapshot snapshot;
    try {
      snapshot = await _signals.snapshot(
        now: now,
        allowSensitiveSignals: preferences.allowSensitiveSignals,
      );
    } catch (_) {
      snapshot = NeuraIntelligenceSnapshot(generatedAt: now, signals: const []);
    }

    // Read local mood history once for every candidate that needs it. This
    // keeps dashboard evaluation consistent and avoids repeated local-store
    // reads during a single app-open pass.
    final recentMoods = await _recentMoodsOrEmpty();
    final candidates = <_BannerCandidate>[
      ..._radar.scan(snapshot: snapshot, now: now).map(_radarBanner),
      ..._initiative
          .scan(routine: routine, now: now)
          .where((candidate) => !_offeredInitiatives.containsKey(candidate.id))
          .map(_initiativeBanner),
    ];
    final relationship = await _relationshipCandidate(now, recentMoods);
    if (relationship != null) candidates.add(relationship);
    final joy = await _joyCandidate(now, snapshot, recentMoods);
    if (joy != null) candidates.add(joy);
    final streakJoy = await _streakJoyCandidate(now);
    if (streakJoy != null) candidates.add(streakJoy);
    if (candidates.isEmpty) return null;

    final inStorm = await _inStormContext(now);
    final eligible = inStorm
        ? candidates
            .where(
              (item) =>
                  item.kind == ProactiveBannerKind.wellness ||
                  item.kind == ProactiveBannerKind.care,
            )
            .toList(growable: false)
        : candidates;
    if (eligible.isEmpty) return null;

    final mood = snapshot.value(NeuraSignalKind.mood);
    final distress = computeDistressScore(
      moodValue: mood,
      recentMoods: recentMoods,
    );
    final cognitive = await _cognitiveSuppressionSignals(now);
    if (!_isCurrent(generation) || SafeBoot.instance.safeMode.value) {
      return null;
    }
    // Consent can change while local stores are being read. Never submit an
    // initiative derived from a revoked routine to the decision history.
    final currentEligible = eligible.where(
      (item) =>
          !item.candidate.specialistId.startsWith('initiative.') ||
          (_canLearnRoutine && routineGeneration == _routineGeneration),
    );
    final council =
        await NeuraIntelligenceController.instance.evaluateCandidates(
      candidates: currentEligible.map((item) => item.candidate),
      now: now,
      distressScore: distress,
      bandwidthStrain: cognitive.bandwidthStrain,
      outcomeLoopSuppression: cognitive.outcomeLoopSuppression,
      roomId: _currentRoomId(),
    );
    if (council.visible.isEmpty) return null;

    final byId = {for (final item in eligible) item.candidate.id: item};
    final lastKind = state['lastKind']?.toString();
    var visible = council.visible;
    final alternate = visible.where((decision) {
      final item = byId[decision.candidate.id];
      return item != null && item.kind.name != lastKind;
    }).toList(growable: false);
    if (alternate.isNotEmpty) visible = alternate;

    final selected = visible.first;
    final source = byId[selected.candidate.id];
    if (source == null ||
        !_isCurrent(generation) ||
        SafeBoot.instance.safeMode.value) {
      return null;
    }
    final banner = source.toBanner(
      selected.receipt,
      generation,
      routineGeneration,
    );
    if (!canDisplay(banner)) return null;
    if (banner.isInitiative) {
      _offeredInitiatives[banner.candidate.id] = (
        expiresAt: banner.candidate.expiresAt,
        receiptId: banner.receipt.id,
      );
    }
    return banner;
  }

  bool canDisplay(ProactiveBanner banner) {
    final now = _clock();
    final preferences = NeuraIntelligenceController.instance.preferences;
    return _isCurrent(banner.dataGeneration) &&
        !SafeBoot.instance.safeMode.value &&
        preferences.allowsProactiveSuggestions &&
        !preferences.isQuietAt(now) &&
        banner.candidate.expiresAt.isAfter(now) &&
        (!banner.isInitiative ||
            (_canLearnRoutine &&
                banner.routineGeneration == _routineGeneration));
  }

  /// An unmounted card has not consumed its welcome-back opportunity.
  void releaseUnshown(ProactiveBanner banner) {
    if (!_shownReceipts.contains(banner.receipt.id) &&
        _offeredInitiatives[banner.candidate.id]?.receiptId ==
            banner.receipt.id) {
      _offeredInitiatives.remove(banner.candidate.id);
    }
  }

  @visibleForTesting
  static Duration cooldownFor(
    NeuraProactivityLevel level, {
    required int consecutiveDismissals,
  }) {
    if (consecutiveDismissals >= _dismissalsBeforeExtendedCooldown) {
      return _extendedCooldown;
    }
    return level.appOpenCooldown;
  }

  /// Commits quota and cooldown only after the dashboard confirms the card
  /// reached a rendered frame.
  Future<void> recordShown(ProactiveBanner banner) async {
    if (!canDisplay(banner) || !_shownReceipts.add(banner.receipt.id)) return;
    if (_shownReceipts.length > 100) {
      _shownReceipts.remove(_shownReceipts.first);
    }
    if (banner.candidate.specialistId ==
        NeuraInitiativeSource.arrivalSpecialist) {
      _routine = _routine?.acknowledgeArrival(banner.candidate.id);
      _persistRoutine();
    }
    await _enqueueWrite((generation) async {
      final state = await _loadState();
      if (!canDisplay(banner) || state['lastReceiptId'] == banner.receipt.id) {
        return;
      }
      final now = _clock();
      await NeuraIntelligenceController.instance.markShown(banner.receipt.id);
      if (!_isCurrent(generation)) return;
      await _saveState({
        ...state,
        'lastShownEpochMs': now.millisecondsSinceEpoch,
        'lastKind': banner.kind.name,
        'lastReceiptId': banner.receipt.id,
      }, generation);
    });
  }

  /// Computes the two "hold back proactive suggestions" signals from the
  /// cognitive/adaptive-intent side of the app that the Autonomy Kernel
  /// previously never saw. Best-effort: any failure (missing history, a
  /// store read error) falls back to "no extra suppression" rather than
  /// blocking the dashboard.
  Future<({double bandwidthStrain, bool outcomeLoopSuppression})>
      _cognitiveSuppressionSignals(DateTime now) async {
    try {
      final liveSignals = await _liveSignals.collect(
        baseline: NeuraCognitiveSignals.defaults(),
      );
      final cognitiveState = _bandwidthEngine.estimate(
        liveSignals.signals,
        safeMode: SafeBoot.instance.safeMode.value,
        calculatedAt: now,
      );
      final history = await _outcomeStore.load();
      final adaptation = _outcomeLoop.evaluate(
        history: history,
        currentState: cognitiveState,
      );
      return (
        bandwidthStrain: cognitiveState.cognitiveLoad,
        outcomeLoopSuppression: adaptation.suppressProactiveSuggestions,
      );
    } catch (_) {
      return (bandwidthStrain: 0.0, outcomeLoopSuppression: false);
    }
  }

  /// Computes the guardrail-facing distress score, bounded to 0..1. The
  /// existing mood estimate remains the baseline, while a corroborated local
  /// detector signal can only raise the score and make Neura more cautious.
  @visibleForTesting
  static double computeDistressScore({
    required double? moodValue,
    required List<int> recentMoods,
    DistressDetector? detector,
  }) {
    final rawMoodDistress = moodValue == null
        ? 0.0
        : ((0.5 - moodValue) * 1.4).clamp(0.0, 0.7).toDouble();
    // A local, reversible Care banner may respond to one sustained,
    // user-recorded low-mood trend. Other DistressDetector consumers keep
    // the more conservative multi-signal threshold of 3.
    final signal =
        (detector ?? const DistressDetector(activationThreshold: 2)).detect(
      recentMoods: recentMoods,
      appOpensLastHour: 0,
      lotsOfNegativeWords: false,
    );
    return signal.active
        ? rawMoodDistress.clamp(0.75, 1.0).toDouble()
        : rawMoodDistress;
  }

  _BannerCandidate _radarBanner(NeuraIntelligenceCandidate candidate) {
    final kind = switch (candidate.payload['opportunity_kind']) {
      'mood_reset' => ProactiveBannerKind.wellness,
      'focus_sprint' => ProactiveBannerKind.focus,
      'care_support' => ProactiveBannerKind.care,
      'dream_pattern_check' => ProactiveBannerKind.dream,
      _ => ProactiveBannerKind.quest,
    };
    return _BannerCandidate(candidate: candidate, kind: kind);
  }

  _BannerCandidate _initiativeBanner(NeuraIntelligenceCandidate candidate) {
    final kind = candidate.payload[NeuraInitiativeSource.kindKey] ==
            NeuraInitiativeSource.routineShiftKind
        ? ProactiveBannerKind.wellness
        : ProactiveBannerKind.presence;
    return _BannerCandidate(candidate: candidate, kind: kind);
  }

  NeuraRoutineModel _loadRoutine() {
    try {
      final raw = NeuraPrefsCache.prefs.getString(_routineKey);
      if (raw == null || raw.trim().isEmpty) return NeuraRoutineModel.empty();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return NeuraRoutineModel.empty();
      return NeuraRoutineModel.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return NeuraRoutineModel.empty();
    }
  }

  void _persistRoutine() {
    if (!_canLearnRoutine || _routine == null) return;
    final routineGeneration = _routineGeneration;
    unawaited(
      _enqueueWrite((generation) async {
        if (!_canLearnRoutine ||
            routineGeneration != _routineGeneration ||
            !_isCurrent(generation)) {
          return;
        }
        await NeuraPrefsCache.prefs.setString(
          _routineKey,
          jsonEncode(_routine!.toJson()),
        );
      }).catchError((_) {}),
    );
  }

  String? _currentRoomId() {
    try {
      return NeuraPrefsCache.prefs.getString(NeuraRoom.currentRoomPrefsKey);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _inStormContext(DateTime now) async {
    try {
      final events = await AfterStormService.instance.loadEvents();
      if (events.isEmpty) return false;
      return now.difference(events.first.timestamp) < _stormSuppressWindow;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>> _recentMoodsNeg2to2() async {
    final entries = await MoodStore.instance.getAll();
    final recent =
        entries.length > 10 ? entries.sublist(entries.length - 10) : entries;
    return recent
        .map(
          (entry) => ((entry.mood0to10 - 5) / 2.5).round().clamp(-2, 2).toInt(),
        )
        .toList(growable: false);
  }

  Future<List<int>> _recentMoodsOrEmpty() async {
    try {
      return await _recentMoodsNeg2to2();
    } catch (_) {
      return const [];
    }
  }

  Future<_BannerCandidate?> _joyCandidate(
    DateTime now,
    NeuraIntelligenceSnapshot snapshot,
    List<int> recentMoods,
  ) async {
    try {
      if (recentMoods.isEmpty) return null;
      final moment = JoyEngine().pickMoment(_mapMood(recentMoods.last));
      final moodSignal = snapshot.signal(NeuraSignalKind.mood);
      final candidate = NeuraIntelligenceCandidate(
        id: 'joy:${moment.id}:${now.year}-${now.month}-${now.day}',
        capabilityId: NeuraCapabilityRegistry.openAppModule,
        specialistId: 'joy_specialist',
        title: moment.title,
        body: moment.description,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 12)),
        evidence: moodSignal?.evidence ?? const [],
        benefit: 0.68,
        urgency: 0.35,
        disruption: 0.12,
        confidence: moodSignal?.confidence ?? 0.7,
        payload: const {'opportunity_kind': 'joy', 'module': 'joy_engine'},
      );
      return _BannerCandidate(
        candidate: candidate,
        kind: ProactiveBannerKind.joy,
        joyMoment: moment,
      );
    } catch (_) {
      return null;
    }
  }

  NeuraMood _mapMood(int score) {
    if (score <= -2) return NeuraMood.sad;
    if (score == -1) return NeuraMood.stressed;
    if (score >= 1) return NeuraMood.energized;
    return NeuraMood.neutral;
  }

  /// Round-number streak lengths worth celebrating. The candidate id embeds
  /// the milestone value itself (not just the date), so this only fires the
  /// day the streak lands exactly on one of these numbers -- naturally once
  /// per milestone, since every other day's streak count misses the list.
  static const List<int> _streakMilestones = [7, 14, 30, 60, 90, 180, 365];

  @visibleForTesting
  static bool isStreakMilestone(int streak) =>
      _streakMilestones.contains(streak);

  Future<_BannerCandidate?> _streakJoyCandidate(DateTime now) async {
    try {
      final streak = await QuestStore.instance.currentStreak();
      if (!isStreakMilestone(streak)) return null;
      final moment = JoyEngine().pickMoment(
        NeuraMood.energized,
        intent: NeuraIntent.seekingProgress,
      );
      final candidate = NeuraIntelligenceCandidate(
        id: 'joy:streak:$streak:${now.year}-${now.month}-${now.day}',
        capabilityId: NeuraCapabilityRegistry.openAppModule,
        specialistId: 'joy_specialist',
        title: '$streak days in a row',
        body: moment.description,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 12)),
        evidence: const [],
        benefit: 0.72,
        urgency: 0.3,
        disruption: 0.12,
        confidence: 0.9,
        payload: {
          'opportunity_kind': 'joy',
          'module': 'joy_engine',
          'streak_days': streak,
        },
      );
      return _BannerCandidate(
        candidate: candidate,
        kind: ProactiveBannerKind.joy,
        joyMoment: moment,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_BannerCandidate?> _relationshipCandidate(
    DateTime now,
    List<int> recentMoods,
  ) async {
    try {
      final profiles = await RelationshipProfileService.instance.all();
      if (profiles.isEmpty) return null;

      RelationshipProfile? mostOverdue;
      int? maxDays;
      for (final profile in profiles) {
        if (profile.lastContact == null) continue;
        final days = now.difference(profile.lastContact!).inDays;
        if (maxDays == null || days > maxDays) {
          maxDays = days;
          mostOverdue = profile;
        }
      }

      const insight = RelationshipInsightService();
      final suggestion = insight.computeOneGoodMove(
        recentMoods: recentMoods,
        promisesOutstanding: profiles.any(
          (profile) => profile.openPromiseCount > 0,
        ),
        daysSinceLastContact: maxDays,
      );
      if (suggestion == null) return null;
      final subject = mostOverdue ?? profiles.first;
      final observedAt = subject.lastContact ?? now;
      final candidate = NeuraIntelligenceCandidate(
        id: 'relationship:${subject.id}:${now.year}-${now.month}',
        capabilityId: NeuraCapabilityRegistry.openAppModule,
        specialistId: 'relationship_specialist',
        title: suggestion.title,
        body: suggestion.description,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 2)),
        evidence: [
          NeuraEvidenceRef(
            id: 'relationship:${subject.id}',
            source: 'relationship_profile',
            summary: 'Local relationship recency and open-promise signal',
            observedAt: observedAt,
            confidence: 0.82,
            sensitivity: NeuraSensitivity.personal,
          ),
        ],
        benefit: 0.7,
        urgency: subject.openPromiseCount > 0 ? 0.68 : 0.42,
        disruption: 0.22,
        confidence: 0.82,
        payload: const {
          'opportunity_kind': 'relationship',
          'module': 'relationships',
        },
      );
      return _BannerCandidate(
        candidate: candidate,
        kind: ProactiveBannerKind.relationship,
        relationshipProfile: mostOverdue,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> recordOutcome({
    required ProactiveBanner banner,
    required bool acted,
  }) async {
    if (!canDisplay(banner)) return;
    await _enqueueWrite((generation) async {
      final state = await _loadState();
      if (!canDisplay(banner)) return;
      final consecutive =
          acted ? 0 : (_coerceInt(state['consecutiveDismissals']) ?? 0) + 1;
      await _saveState({
        ...state,
        'consecutiveDismissals': consecutive,
      }, generation);
      if (!_isCurrent(generation)) return;
      await NeuraIntelligenceController.instance.recordOutcome(
        receiptId: banner.receipt.id,
        acted: acted,
      );

      if (!_isCurrent(generation) ||
          !HumanPrefsController.instance.prefs.value.allowLearning) {
        return;
      }
      try {
        await MemoryGraphService.I.logSuggestion(
          kind: 'PROACTIVE_BANNER',
          payload: {
            'specialist': banner.receipt.specialistId,
            'capability': banner.receipt.capabilityId,
          },
          outcome: acted ? 'acted' : 'dismissed',
        );
      } catch (_) {
        // Optional local learning cannot block the dashboard.
      }
    });
  }

  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _dataGeneration += 1;
    _routineGeneration += 1;
    _routine = NeuraRoutineModel.empty();
    _offeredInitiatives.clear();
    _shownReceipts.clear();
    await _writeQueue.timeout(const Duration(seconds: 3));
  }

  void resumeAfterDataWipe() {
    if (_pendingWrites != 0) {
      throw StateError(
        'Proactive writes have not drained. Retry data removal.',
      );
    }
    _writesSuspended = false;
  }

  Future<void> _enqueueWrite(Future<void> Function(int generation) operation) {
    if (_writesSuspended) return Future<void>.value();
    final generation = _dataGeneration;
    _pendingWrites += 1;
    final next = _writeQueue
        .then(
          (_) => _isCurrent(generation)
              ? operation(generation)
              : Future<void>.value(),
          onError: (_) => _isCurrent(generation)
              ? operation(generation)
              : Future<void>.value(),
        )
        .whenComplete(() => _pendingWrites -= 1);
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  bool _isCurrent(int generation) =>
      !_writesSuspended && generation == _dataGeneration;

  int? _coerceInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
