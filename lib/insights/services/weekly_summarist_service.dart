import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../profiles/local_profile_service.dart';
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

/// What the user said was wrong with a weekly narrative. Each maps to a
/// fixed line of guidance for the next draft, so the user's own words never
/// enter the prompt.
enum WeeklyNarrativeCorrection {
  tooHarsh(
    'Too harsh',
    'The reader found last week’s narrative too harsh: be gentler and lead '
        'with what went well.',
  ),
  tooRosy(
    'Too rosy',
    'The reader found last week’s narrative too rosy: be honest about the '
        'harder parts, kindly.',
  ),
  missedWhatMattered(
    'Missed what mattered',
    'The reader said last week’s narrative missed what mattered: stay close '
        'to the numbers and do not guess at causes.',
  ),
  tooLong(
    'Too long',
    'The reader found last week’s narrative too long: use three short '
        'sentences.',
  );

  const WeeklyNarrativeCorrection(this.label, this.guidance);

  /// What the user picks.
  final String label;

  /// The line added to the next draft's prompt.
  final String guidance;

  static WeeklyNarrativeCorrection? byName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
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
  WeeklySummaristService._({Future<String> Function(String)? draft})
      : _draft = draft;
  static final WeeklySummaristService instance = WeeklySummaristService._();

  @visibleForTesting
  factory WeeklySummaristService.forTesting({
    required Future<String> Function(String) draft,
  }) =>
      WeeklySummaristService._(draft: draft);

  final Future<String> Function(String)? _draft;

  static const _key = 'neura.weekly_summarist_state.v1';
  static const _correctionKey = 'neura.weekly_summarist_correction.v1';
  static const _staleAfter = Duration(days: 7);

  Future<void>? _inFlight;
  int _dataGeneration = 0;
  int _correctionRevision = 0;
  Future<void> _correctionTail = Future<void>.value();
  bool _suspended = false;

  bool get _available => !_suspended && !LocalProfileService.instance.enabled;
  void invalidateSession() {
    _dataGeneration++;
  }

  void suspendForDataWipe() {
    _suspended = true;
    invalidateSession();
  }

  Future<void> drainForDataWipe() => Future.wait<void>([
        if (_inFlight != null) _inFlight!,
        _correctionTail,
      ]).timeout(const Duration(seconds: 30));

  @visibleForTesting
  static void resetWipeGateForTesting() {
    instance._suspended = false;
    instance._dataGeneration++;
  }

  Future<T> _correctionOperation<T>(Future<T> Function() operation) {
    final next = _correctionTail.then((_) => operation());
    _correctionTail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<WeeklyNarrativeState?> _load() async {
    if (!_available) return null;
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

  Future<bool> _save(WeeklyNarrativeState state, int generation) async {
    if (!_available || generation != _dataGeneration) return false;
    final prefs = NeuraPrefsCache.prefs;
    final saved = await prefs.setString(_key, jsonEncode(state.toMap()));
    if (!saved) {
      await prefs.reload();
      throw StateError('The weekly draft could not be saved on this device.');
    }
    return _available && generation == _dataGeneration;
  }

  /// The correction the user gave the last narrative, until the next draft
  /// has taken it into account.
  WeeklyNarrativeCorrection? get pendingCorrection => !_available
      ? null
      : WeeklyNarrativeCorrection.byName(
          NeuraPrefsCache.prefsOrNull?.getString(_correctionKey),
        );

  /// Records what was wrong with the current narrative. The next weekly
  /// draft follows the matching guidance; the current one is unchanged.
  Future<void> recordCorrection(WeeklyNarrativeCorrection correction) {
    final generation = _dataGeneration;
    final epoch = LocalProfileService.instance.epoch;
    if (!_available) return Future.error(StateError('Correction unavailable.'));
    return _correctionOperation(() async {
      if (!_available ||
          generation != _dataGeneration ||
          epoch != LocalProfileService.instance.epoch) {
        throw StateError('This correction request has expired.');
      }
      final prefs = NeuraPrefsCache.prefs;
      final saved = await prefs.setString(_correctionKey, correction.name);
      if (!_available ||
          generation != _dataGeneration ||
          epoch != LocalProfileService.instance.epoch) {
        throw StateError('This correction request has expired.');
      }
      if (!saved) {
        await prefs.reload();
        throw StateError('The correction could not be saved on this device.');
      }
      // Revision belongs to this confirmed write, including repeated choices.
      _correctionRevision++;
    });
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
    if (!_available) return Future.value();
    final existing = _inFlight;
    if (existing != null) return existing;

    final generation = _dataGeneration;
    final future =
        _generateIfDue(generation).whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<void> resetAfterDataWipe() async {
    suspendForDataWipe();
    await drainForDataWipe();
  }

  Future<void> _generateIfDue(int generation) async {
    final epoch = LocalProfileService.instance.epoch;
    bool current() =>
        _available &&
        generation == _dataGeneration &&
        epoch == LocalProfileService.instance.epoch;
    if (!current() || !await isDue()) return;
    if (!current()) return;
    if (_draft == null && !NeuraAiService.instance.isConfigured) return;

    try {
      final review = await WeeklyReviewStore.instance.generate();
      if (!current()) return;
      final summary = await WeeklySnapshotService.instance.buildSummary();
      if (!current()) return;

      final prompt =
          'week of ${review.weekStart.toIso8601String().substring(0, 10)}: '
          'mood avg ${review.moodAvg}/10 (min ${review.moodMin}, max ${review.moodMax}) '
          'across ${review.moodSamples} check-ins; '
          'kindness acts ${review.kindnessActs}; quests done ${review.questDone}; '
          '${review.topLearned.isEmpty ? 'no standout helpful categories' : 'top helpful categories ${review.topLearned.join(', ')}'}; '
          'storms ${summary.stormsCount} (safety-flagged ${summary.safetyStormsCount}); '
          'dreams ${summary.dreamsCount}; '
          'most common storm feeling ${summary.topStormFeeling}; '
          'recurring dream theme ${summary.topDreamTheme}. '
          'Write a short (3-5 sentence) second-person narrative using only these numbers.';
      // Snapshot content and its committed revision in the same serialized turn.
      final correctionSnapshot = await _correctionOperation(() async =>
          (correction: pendingCorrection, revision: _correctionRevision));
      if (!current()) return;
      final correctionRevision = correctionSnapshot.revision;
      final correction = correctionSnapshot.correction;
      final guided =
          correction == null ? prompt : '$prompt ${correction.guidance}';

      if (!current()) return;
      final draft = _draft;
      final text = draft != null
          ? await draft(guided)
          : await NeuraAiService.instance.completeOnce(
              guided,
              agentId: AgentPersonaCatalog.weeklySummarist.id,
            );

      if (!current()) return;
      final saved = await _save(
          WeeklyNarrativeState(
            summaryText: text,
            generatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
          ),
          generation);
      // The correction has shaped this draft; the next one starts fresh.
      if (saved && correction != null) {
        await _correctionOperation(() async {
          if (!current() || correctionRevision != _correctionRevision) return;
          if (!await NeuraPrefsCache.prefs.remove(_correctionKey)) {
            throw StateError('The used correction could not be cleared.');
          }
        });
      }
    } catch (e, st) {
      if (!current()) return;
      // Network failure, guardrail block (NeuraGuardrailBlocked), or missing
      // key -- don't persist anything, stay "due", retry next app-open. The
      // weekly snapshot screen just shows its existing deterministic cards.
      await AppLog.instance.caught('weekly_summarist_generate_failed', e, st);
    }
  }
}
