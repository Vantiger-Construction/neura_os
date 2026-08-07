import 'dart:async';
import 'dart:convert';

import '../after_storm/services/after_storm_service.dart';
import '../core/memory/memory_graph_service.dart';
import '../joy_engine/joy_engine.dart';
import '../joy_engine/joy_types.dart';
import '../modules/mood/mood_store.dart';
import '../relationships/models/relationship_profile.dart';
import '../relationships/services/relationship_insight_service.dart';
import '../relationships/services/relationship_profile_service.dart';
import '../startup/neura_prefs_cache.dart';

enum ProactiveBannerKind { joy, relationship }

class ProactiveBanner {
  final ProactiveBannerKind kind;
  final String title;
  final String body;
  final JoyMoment? joyMoment;
  final RelationshipProfile? relationshipProfile;

  const ProactiveBanner({
    required this.kind,
    required this.title,
    required this.body,
    this.joyMoment,
    this.relationshipProfile,
  });
}

/// Decides whether to surface an unprompted dashboard banner (a Joy Moment
/// or a relationship nudge) on app open, and picks which one.
///
/// This is genuinely new decision logic -- unlike most of this app's
/// features, there's no existing rules engine worth inheriting here (see
/// lib/behavior/, which is scaffolding with no real logic behind it).
class ProactiveBannerService {
  ProactiveBannerService._();
  static final ProactiveBannerService instance = ProactiveBannerService._();

  static const _stateKey = 'neura.proactive_banner.state.v1';

  /// Baseline "don't be naggy" cooldown between any two banners.
  static const _cooldown = Duration(hours: 12);

  /// After this many dismissals in a row, extend the cooldown a lot rather
  /// than keep asking at the normal cadence -- a soft, gradual suppression
  /// for a feature the user keeps declining, without a settings toggle.
  static const _extendedCooldown = Duration(days: 7);
  static const _dismissalsBeforeExtendedCooldown = 3;

  /// Only relevant while a relationship nudge is being considered -- doesn't
  /// gate Joy Moments as tightly, but a storm/crisis context shouldn't
  /// compete for attention with *either* kind of cheerful/ask-more nudge.
  static const _stormSuppressWindow = Duration(hours: 24);

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

  Future<void> _saveState(Map<String, dynamic> state) async {
    await NeuraPrefsCache.prefs.setString(_stateKey, jsonEncode(state));
  }

  Future<ProactiveBanner?> maybeGetBannerOnAppOpen() async {
    final state = await _loadState();
    final now = DateTime.now();

    final lastShownMs = state['lastShownEpochMs'] as int?;
    final consecutiveDismissals = (state['consecutiveDismissals'] as int?) ?? 0;
    if (lastShownMs != null) {
      final lastShown = DateTime.fromMillisecondsSinceEpoch(lastShownMs);
      final cooldown = consecutiveDismissals >= _dismissalsBeforeExtendedCooldown
          ? _extendedCooldown
          : _cooldown;
      if (now.isBefore(lastShown.add(cooldown))) return null;
    }

    if (await _inStormContext(now)) return null;

    final lastKind = state['lastKind'] as String?;
    final relationship = await _relationshipCandidate();
    final joy = await _joyCandidate();

    ProactiveBanner? chosen;
    if (relationship != null && joy != null) {
      chosen = lastKind == 'relationship' ? joy : relationship;
    } else {
      chosen = relationship ?? joy;
    }
    if (chosen == null) return null;

    await _saveState({
      ...state,
      'lastShownEpochMs': now.millisecondsSinceEpoch,
      'lastKind': chosen.kind == ProactiveBannerKind.joy ? 'joy' : 'relationship',
    });
    return chosen;
  }

  Future<bool> _inStormContext(DateTime now) async {
    try {
      final events = await AfterStormService.instance.loadEvents();
      if (events.isEmpty) return false;
      // loadEvents() returns newest-first.
      return now.difference(events.first.timestamp) < _stormSuppressWindow;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>> _recentMoodsNeg2to2() async {
    final entries = await MoodStore.instance.getAll();
    final recent = entries.length > 10 ? entries.sublist(entries.length - 10) : entries;
    return recent.map((e) => ((e.mood0to10 - 5) / 2.5).round().clamp(-2, 2)).toList();
  }

  Future<ProactiveBanner?> _joyCandidate() async {
    try {
      final moods = await _recentMoodsNeg2to2();
      if (moods.isEmpty) return null;
      final mapped = _mapMood(moods.last);
      final moment = JoyEngine().pickMoment(mapped);
      return ProactiveBanner(
        kind: ProactiveBannerKind.joy,
        title: 'A small moment?',
        body: moment.description,
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

  Future<ProactiveBanner?> _relationshipCandidate() async {
    try {
      final profiles = await RelationshipProfileService.instance.all();
      if (profiles.isEmpty) return null;

      RelationshipProfile? mostOverdue;
      int? maxDays;
      final now = DateTime.now();
      for (final p in profiles) {
        if (p.lastContact == null) continue;
        final days = now.difference(p.lastContact!).inDays;
        if (maxDays == null || days > maxDays) {
          maxDays = days;
          mostOverdue = p;
        }
      }

      final moods = await _recentMoodsNeg2to2();
      const insight = RelationshipInsightService();
      final suggestion = insight.computeOneGoodMove(
        recentMoods: moods,
        promisesOutstanding: profiles.any((p) => p.openPromiseCount > 0),
        daysSinceLastContact: maxDays,
      );
      if (suggestion == null) return null;

      return ProactiveBanner(
        kind: ProactiveBannerKind.relationship,
        title: suggestion.title,
        body: suggestion.description,
        relationshipProfile: mostOverdue,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> recordOutcome({required bool acted}) async {
    final state = await _loadState();
    final consecutive = acted ? 0 : ((state['consecutiveDismissals'] as int?) ?? 0) + 1;
    await _saveState({...state, 'consecutiveDismissals': consecutive});
    try {
      await MemoryGraphService.I.logSuggestion(
        kind: 'PROACTIVE_BANNER',
        payload: {},
        outcome: acted ? 'acted' : 'dismissed',
      );
    } catch (_) {
      // Non-critical.
    }
  }
}
