import 'dart:convert';

import '../after_storm/services/after_storm_service.dart';
import '../core/memory/memory_graph_service.dart';
import '../intelligence/capability_registry.dart';
import '../intelligence/models.dart';
import '../intelligence/neura_intelligence_controller.dart';
import '../intelligence/opportunity_radar.dart';
import '../intelligence/runtime_signal_adapter.dart';
import '../joy_engine/joy_engine.dart';
import '../joy_engine/joy_types.dart';
import '../modules/human/human_prefs_controller.dart';
import '../modules/mood/mood_store.dart';
import '../relationships/models/relationship_profile.dart';
import '../relationships/services/relationship_insight_service.dart';
import '../relationships/services/relationship_profile_service.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';

enum ProactiveBannerKind { joy, relationship, quest, wellness, focus, care }

class ProactiveBanner {
  const ProactiveBanner({
    required this.kind,
    required this.title,
    required this.body,
    required this.candidate,
    required this.receipt,
    this.joyMoment,
    this.relationshipProfile,
  });

  final ProactiveBannerKind kind;
  final String title;
  final String body;
  final NeuraIntelligenceCandidate candidate;
  final NeuraDecisionReceipt receipt;
  final JoyMoment? joyMoment;
  final RelationshipProfile? relationshipProfile;
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

  ProactiveBanner toBanner(NeuraDecisionReceipt receipt) => ProactiveBanner(
        kind: kind,
        title: candidate.title,
        body: candidate.body,
        candidate: candidate,
        receipt: receipt,
        joyMoment: joyMoment,
        relationshipProfile: relationshipProfile,
      );
}

/// Builds local opportunities and sends every one through Neura's privacy,
/// attention, consent, and guardrail boundary before it reaches the dashboard.
class ProactiveBannerService {
  ProactiveBannerService._();

  static final ProactiveBannerService instance = ProactiveBannerService._();

  static const _stateKey = 'neura.proactive_banner.state.v2';
  static const _cooldown = Duration(hours: 12);
  static const _extendedCooldown = Duration(days: 7);
  static const _dismissalsBeforeExtendedCooldown = 3;
  static const _stormSuppressWindow = Duration(hours: 24);

  final NeuraRuntimeSignalAdapter _signals = const NeuraRuntimeSignalAdapter();
  final NeuraOpportunityRadar _radar = const NeuraOpportunityRadar();
  Future<void> _writeQueue = Future<void>.value();
  bool _writesSuspended = false;
  int _dataGeneration = 0;

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

  Future<void> _saveState(
    Map<String, dynamic> state,
    int generation,
  ) async {
    await NeuraPrefsCache.prefs.setString(_stateKey, jsonEncode(state));
    if (!_isCurrent(generation)) {
      await NeuraPrefsCache.prefs.remove(_stateKey);
    }
  }

  Future<ProactiveBanner?> maybeGetBannerOnAppOpen() async {
    if (SafeBoot.instance.safeMode.value) return null;
    await NeuraIntelligenceController.instance.initialize();
    final preferences = NeuraIntelligenceController.instance.preferences;
    final now = DateTime.now();
    if (!preferences.enabled || preferences.isQuietAt(now)) return null;

    final state = await _loadState();
    final lastShownMs = _coerceInt(state['lastShownEpochMs']);
    final consecutiveDismissals =
        _coerceInt(state['consecutiveDismissals']) ?? 0;
    if (lastShownMs != null) {
      final lastShown = DateTime.fromMillisecondsSinceEpoch(lastShownMs);
      final cooldown =
          consecutiveDismissals >= _dismissalsBeforeExtendedCooldown
              ? _extendedCooldown
              : _cooldown;
      if (now.isBefore(lastShown.add(cooldown))) return null;
    }

    NeuraIntelligenceSnapshot snapshot;
    try {
      snapshot = await _signals.snapshot(
        now: now,
        allowSensitiveSignals: preferences.allowSensitiveSignals,
      );
    } catch (_) {
      snapshot = NeuraIntelligenceSnapshot(
        generatedAt: now,
        signals: const [],
      );
    }

    final candidates = <_BannerCandidate>[
      ..._radar.scan(snapshot: snapshot, now: now).map(_radarBanner),
    ];
    final relationship = await _relationshipCandidate(now);
    if (relationship != null) candidates.add(relationship);
    final joy = await _joyCandidate(now, snapshot);
    if (joy != null) candidates.add(joy);
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
    final distress =
        mood == null ? 0.0 : ((0.5 - mood) * 1.4).clamp(0.0, 0.7).toDouble();
    final council =
        await NeuraIntelligenceController.instance.evaluateCandidates(
      candidates: eligible.map((item) => item.candidate),
      now: now,
      distressScore: distress,
    );
    if (council.visible.isEmpty) return null;

    final byId = {
      for (final item in eligible) item.candidate.id: item,
    };
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
        _writesSuspended ||
        SafeBoot.instance.safeMode.value) {
      return null;
    }
    return source.toBanner(selected.receipt);
  }

  /// Commits quota and cooldown only after the dashboard confirms the card
  /// reached a rendered frame.
  Future<void> recordShown(ProactiveBanner banner) async {
    await _enqueueWrite((generation) async {
      final state = await _loadState();
      if (!_isCurrent(generation) ||
          state['lastReceiptId'] == banner.receipt.id) {
        return;
      }
      final now = DateTime.now();
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

  _BannerCandidate _radarBanner(NeuraIntelligenceCandidate candidate) {
    final kind = switch (candidate.payload['opportunity_kind']) {
      'mood_reset' => ProactiveBannerKind.wellness,
      'focus_sprint' => ProactiveBannerKind.focus,
      'care_support' => ProactiveBannerKind.care,
      _ => ProactiveBannerKind.quest,
    };
    return _BannerCandidate(candidate: candidate, kind: kind);
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

  Future<_BannerCandidate?> _joyCandidate(
    DateTime now,
    NeuraIntelligenceSnapshot snapshot,
  ) async {
    try {
      final moods = await _recentMoodsNeg2to2();
      if (moods.isEmpty) return null;
      final moment = JoyEngine().pickMoment(_mapMood(moods.last));
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
        payload: const {
          'opportunity_kind': 'joy',
          'module': 'joy_engine',
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

  NeuraMood _mapMood(int score) {
    if (score <= -2) return NeuraMood.sad;
    if (score == -1) return NeuraMood.stressed;
    if (score >= 1) return NeuraMood.energized;
    return NeuraMood.neutral;
  }

  Future<_BannerCandidate?> _relationshipCandidate(DateTime now) async {
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

      final moods = await _recentMoodsNeg2to2();
      const insight = RelationshipInsightService();
      final suggestion = insight.computeOneGoodMove(
        recentMoods: moods,
        promisesOutstanding:
            profiles.any((profile) => profile.openPromiseCount > 0),
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
    await _enqueueWrite((generation) async {
      final state = await _loadState();
      if (!_isCurrent(generation)) return;
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
    await _writeQueue.timeout(const Duration(seconds: 3));
    _writeQueue = Future<void>.value();
  }

  void resumeAfterDataWipe() {
    _writeQueue = Future<void>.value();
    _writesSuspended = false;
  }

  Future<void> _enqueueWrite(
    Future<void> Function(int generation) operation,
  ) {
    if (_writesSuspended) return Future<void>.value();
    final generation = _dataGeneration;
    final next = _writeQueue.then(
      (_) =>
          _isCurrent(generation) ? operation(generation) : Future<void>.value(),
      onError: (_) =>
          _isCurrent(generation) ? operation(generation) : Future<void>.value(),
    );
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
