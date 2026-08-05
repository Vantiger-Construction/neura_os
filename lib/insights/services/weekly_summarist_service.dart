import 'dart:async';
import 'dart:convert';

import '../../modules/core/app_log.dart';
import '../../modules/review/weekly_review_store.dart';
import '../../persona/agents/agent_persona_catalog.dart';
import '../../services/neura_ai_service.dart';
import '../../startup/neura_prefs_cache.dart';
import '../../weekly/services/weekly_snapshot_service.dart';

/// A stored weekly narrative and when it was drafted.
class WeeklyNarrativeState {
  final String summaryText;
  final int generatedAtEpochMs;

  const WeeklyNarrativeState({
    required this.summaryText,
    required this.generatedAtEpochMs,
  });

  DateTime get generatedAt =>
      DateTime.fromMillisecondsSinceEpoch(generatedAtEpochMs);

  Map<String, dynamic> toMap() => {
        'summaryText': summaryText,
        'generatedAtEpochMs': generatedAtEpochMs,
      };

  static WeeklyNarrativeState? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final text = map['summaryText']?.toString();
    final epoch = int.tryParse(map['generatedAtEpochMs']?.toString() ?? '');
    if (text == null || text.isEmpty || epoch == null) return null;
    return WeeklyNarrativeState(summaryText: text, generatedAtEpochMs: epoch);
  }
}

/// Drafts a short LLM-written weekly narrative, at most once every 7 days.
///
/// Platform note: there is no OS-level scheduler in this app, and Flutter
/// on Windows cannot run code while the app process isn't running.
/// [maybeGenerateOnAppOpen] is meant to be called once per app launch (see
/// [lib/modules/navigation/enhanced_navigation.dart]) -- this is a
/// cadence-gated task that runs while the app is open, not a background
/// service, push notification, or anything native.
///
/// Input is deliberately restricted to already-aggregated weekly stats
/// ([WeeklyReviewStore], [WeeklySnapshotService]) -- no raw mood notes, chat
/// history, or journal/dream entry text is ever read here, keeping this
/// feature's privacy surface identical to what [WeeklySnapshotScreen]
/// already shows today, just narrated instead of tabulated.
class WeeklySummaristService {
  WeeklySummaristService._();
  static final WeeklySummaristService instance = WeeklySummaristService._();

  static const _key = 'neura.weekly_summarist_state.v1';
  static const _staleAfter = Duration(days: 7);

  Future<void>? _inFlight;

  Future<WeeklyNarrativeState?> _load() async {
    try {
      final prefs = NeuraPrefsCache.prefs;
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WeeklyNarrativeState.fromMap(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(WeeklyNarrativeState state) async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_key, jsonEncode(state.toMap()));
  }

  Future<bool> isDue({DateTime? now}) async {
    final state = await _load();
    if (state == null) return true;
    return (now ?? DateTime.now()).isAfter(state.generatedAt.add(_staleAfter));
  }

  /// Returns the stored narrative only if it's still within the freshness
  /// window -- a stale one from a prior cycle is never surfaced even if
  /// regeneration hasn't completed yet this session.
  Future<WeeklyNarrativeState?> currentIfFresh({DateTime? now}) async {
    final state = await _load();
    if (state == null) return null;
    final stale =
        (now ?? DateTime.now()).isAfter(state.generatedAt.add(_staleAfter));
    return stale ? null : state;
  }

  /// Call once per app launch (no [BuildContext] needed -- this never shows
  /// UI itself, it only writes to prefs). Concurrent callers collapse into
  /// one HTTP call via [_inFlight].
  Future<void> maybeGenerateOnAppOpen() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _generateIfDue().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<void> _generateIfDue() async {
    if (!await isDue()) return;
    if (!NeuraAiService.instance.isConfigured) return;

    try {
      final review = await WeeklyReviewStore.instance.generate();
      final summary = await WeeklySnapshotService.instance.buildSummary();

      final prompt = 'week of ${review.weekStart.toIso8601String().substring(0, 10)}: '
          'mood avg ${review.moodAvg}/10 (min ${review.moodMin}, max ${review.moodMax}) '
          'across ${review.moodSamples} check-ins; '
          'kindness acts ${review.kindnessActs}; quests done ${review.questDone}; '
          '${review.topLearned.isEmpty ? 'no standout helpful categories' : 'top helpful categories ${review.topLearned.join(', ')}'}; '
          'storms ${summary.stormsCount} (safety-flagged ${summary.safetyStormsCount}); '
          'dreams ${summary.dreamsCount}; '
          'most common storm feeling ${summary.topStormFeeling}; '
          'recurring dream theme ${summary.topDreamTheme}. '
          'Write a short (3-5 sentence) second-person narrative using only these numbers.';

      final text = await NeuraAiService.instance.completeOnce(
        prompt,
        agentId: AgentPersonaCatalog.weeklySummarist.id,
      );

      await _save(WeeklyNarrativeState(
        summaryText: text,
        generatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (e) {
      // Network failure, guardrail block (NeuraGuardrailBlocked), or missing
      // key -- don't persist anything, stay "due", retry next app-open. The
      // weekly snapshot screen just shows its existing deterministic cards.
      await AppLog.instance.warn('weekly_summarist_generate_failed: $e');
    }
  }
}
