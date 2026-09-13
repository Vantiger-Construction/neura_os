import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import '../guardrails/guardrails.dart';
import '../guardrails/guardrails_types.dart';
import '../reliability/safe_boot.dart';
import '../reliability/timeline_vault.dart';
import '../src/modules/focus/focus_controller.dart';
import '../startup/neura_prefs_cache.dart';
import 'autonomy_kernel.dart';
import 'intelligence_preferences.dart';
import 'models.dart';

/// Local-first coordinator for Neura's proactive intelligence.
///
/// It is deliberately a decision boundary, not an action runner: candidates
/// are fused and scored elsewhere, then evaluated here against attention,
/// privacy, Safe Mode, consent, and the existing app guardrails. Any mutation
/// or external effect must still pass through the approval broker.
class NeuraIntelligenceController extends ChangeNotifier {
  NeuraIntelligenceController._();

  static final NeuraIntelligenceController instance =
      NeuraIntelligenceController._();

  static const _stateKey = 'neura.intelligence.state.v1';
  static const _maxReceipts = 100;

  /// How far each new outcome pulls a specialist's reputation back toward
  /// neutral (1.0) before applying the outcome's own nudge. Keeps stale
  /// history from permanently capping a specialist's score.
  static const _reputationDecay = 0.12;
  static const _reputationStep = 0.06;

  final NeuraAutonomyKernel _kernel = NeuraAutonomyKernel();
  final Guardrails _guardrails = Guardrails();

  NeuraIntelligencePreferences _preferences =
      const NeuraIntelligencePreferences();
  List<NeuraIntelligenceRecord> _records = [];
  Map<String, double> _specialistReputation = {};
  NeuraCouncilResult _lastCouncil = const NeuraCouncilResult([]);
  Future<void> _writeQueue = Future<void>.value();
  bool _initialized = false;
  bool _writesSuspended = false;
  int _dataGeneration = 0;

  NeuraIntelligencePreferences get preferences => _preferences;
  List<NeuraIntelligenceRecord> get records => List.unmodifiable(_records);
  NeuraCouncilResult get lastCouncil => _lastCouncil;
  bool get initialized => _initialized;

  /// The learned confidence multiplier for [specialistId], derived only from
  /// bounded, non-content outcome history (accepted/dismissed counts) — never
  /// from suggestion text. Defaults to 1.0 (neutral) when there is no history.
  double specialistReputation(String specialistId) =>
      _specialistReputation[specialistId] ?? 1.0;

  Future<void> initialize() async {
    if (_initialized || _writesSuspended) return;
    final raw = NeuraPrefsCache.prefs.getString(_stateKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final state = Map<String, Object?>.from(decoded);
          final rawPreferences = state['preferences'];
          if (rawPreferences is Map) {
            _preferences = NeuraIntelligencePreferences.fromJson(
              Map<String, Object?>.from(rawPreferences),
            );
          }
          final rawRecords = state['records'];
          if (rawRecords is List) {
            _records = rawRecords
                .whereType<Map>()
                .map(
                  (item) => NeuraIntelligenceRecord.fromJson(
                    Map<String, Object?>.from(item),
                  ),
                )
                .where((item) => item.receipt.id.isNotEmpty)
                .toList(growable: true);
            _trimRecords();
          }
          final rawReputation = state['specialist_reputation'];
          if (rawReputation is Map) {
            _specialistReputation = {
              for (final entry in rawReputation.entries)
                entry.key.toString(): _double(entry.value, 1.0).clamp(
                  NeuraAutonomyKernel.minSpecialistReputation,
                  NeuraAutonomyKernel.maxSpecialistReputation,
                ),
            };
          }
        }
      } catch (_) {
        _preferences = const NeuraIntelligencePreferences();
        _records = [];
        _specialistReputation = {};
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<NeuraCouncilResult> evaluateCandidates({
    required Iterable<NeuraIntelligenceCandidate> candidates,
    DateTime? now,
    double distressScore = 0,
  }) async {
    if (_writesSuspended) return const NeuraCouncilResult([]);
    final generation = _dataGeneration;
    await initialize();
    if (!_isCurrent(generation)) return const NeuraCouncilResult([]);
    final evaluatedAt = now ?? DateTime.now();
    final startOfDay = DateTime(
      evaluatedAt.year,
      evaluatedAt.month,
      evaluatedAt.day,
    );
    final startOfHour = evaluatedAt.subtract(const Duration(hours: 1));
    final surfaced = _records.where(_wasSurfaced);
    final suggestionsToday = surfaced
        .where((item) => !item.receipt.evaluatedAt.isBefore(startOfDay))
        .length;
    final suggestionsLastHour = surfaced
        .where((item) => !item.receipt.evaluatedAt.isBefore(startOfHour))
        .length;
    final recentlyDeclined = _records.any(
      (item) =>
          item.receipt.userOutcome == NeuraSuggestionOutcome.dismissed &&
          item.receipt.evaluatedAt.isAfter(
            evaluatedAt.subtract(const Duration(hours: 24)),
          ),
    );
    final focusMode = FocusController.instance.state.value.mode.name;
    final quiet = _preferences.isQuietAt(evaluatedAt);
    final policy = NeuraAutonomyPolicy(
      enabled: _preferences.enabled,
      allowSensitiveSignals: _preferences.allowSensitiveSignals,
      maxDailySuggestions: _preferences.maxDailySuggestions,
      suggestionsToday: suggestionsToday,
      suggestionsLastHour: suggestionsLastHour,
      focusMode: focusMode,
      safeMode: SafeBoot.instance.safeMode.value,
      recentlyDeclined: recentlyDeclined,
      quietHours: quiet,
      specialistReputation: Map.unmodifiable(_specialistReputation),
    );

    final decisions = <NeuraCouncilDecision>[];
    for (final candidate in candidates) {
      var receipt = _kernel.evaluate(
        candidate: candidate,
        policy: policy,
        now: evaluatedAt,
      );
      if (receipt.isVisible) {
        final guardrailDecision = _guardrails.evaluate(
          context: NeuraContextSnapshot(
            now: evaluatedAt,
            promptsLastHour: suggestionsLastHour,
            promptsLastDay: suggestionsToday,
            userInFocusMode: focusMode == 'deepWork' || focusMode == 'windDown',
            userSleepingMode: quiet,
            userRecentlyDeclined: recentlyDeclined,
            distressScore: distressScore.clamp(0.0, 1.0).toDouble(),
          ),
          proposal: NeuraProposal(
            type: ProposalType.prompt,
            id: candidate.id,
            message: candidate.body,
            options: const ['open', 'no_thanks'],
            payload: Map<String, dynamic>.from(candidate.payload),
          ),
        );
        if (!guardrailDecision.allow) {
          receipt = receipt.copyWith(
            outcome: NeuraDecisionOutcome.suppressed,
            requiresApproval: false,
            reasons: List.unmodifiable([
              ...receipt.reasons,
              'Existing app guardrail: ${guardrailDecision.reason}',
            ]),
          );
        }
      }
      decisions
          .add(NeuraCouncilDecision(candidate: candidate, receipt: receipt));
      _records.add(
        NeuraIntelligenceRecord(
          title: candidate.title,
          body: candidate.body,
          receipt: receipt,
        ),
      );
      NeuraEventBus.I.emit(
        NeuraIntelligenceEvaluatedEvent(
          receiptId: receipt.id,
          capabilityId: receipt.capabilityId,
          outcome: receipt.outcome.name,
          score: receipt.score,
        ),
      );
    }

    _lastCouncil = NeuraCouncilResult(List.unmodifiable(decisions));
    _trimRecords();
    notifyListeners();
    await _persist();
    if (!_isCurrent(generation)) return const NeuraCouncilResult([]);
    for (final decision in decisions) {
      if (!_isCurrent(generation)) break;
      await _appendTimeline('intelligence_evaluated', decision.receipt);
    }
    return _isCurrent(generation) ? _lastCouncil : const NeuraCouncilResult([]);
  }

  Future<void> markShown(String receiptId) => _updateOutcome(
        receiptId,
        NeuraSuggestionOutcome.shown,
      );

  Future<void> recordOutcome({
    required String receiptId,
    required bool acted,
  }) {
    return _updateOutcome(
      receiptId,
      acted ? NeuraSuggestionOutcome.acted : NeuraSuggestionOutcome.dismissed,
    );
  }

  Future<void> updatePreferences(
    NeuraIntelligencePreferences preferences,
  ) async {
    if (_writesSuspended) return;
    await initialize();
    if (_writesSuspended) return;
    _preferences = preferences;
    notifyListeners();
    await _persist();
  }

  Future<void> pauseFor(Duration duration) {
    return updatePreferences(
      _preferences.copyWith(pausedUntil: DateTime.now().add(duration)),
    );
  }

  Future<void> resume() {
    return updatePreferences(_preferences.copyWith(clearPause: true));
  }

  Future<void> clearHistory() async {
    if (_writesSuspended) return;
    await initialize();
    if (_writesSuspended) return;
    _records = [];
    _lastCouncil = const NeuraCouncilResult([]);
    notifyListeners();
    await _persist();
  }

  Future<void> _updateOutcome(
    String receiptId,
    NeuraSuggestionOutcome outcome,
  ) async {
    if (_writesSuspended) return;
    final generation = _dataGeneration;
    await initialize();
    if (!_isCurrent(generation)) return;
    final index = _records.lastIndexWhere(
      (item) => item.receipt.id == receiptId,
    );
    if (index < 0) return;
    final current = _records[index];
    if (current.receipt.userOutcome == NeuraSuggestionOutcome.acted ||
        current.receipt.userOutcome == NeuraSuggestionOutcome.dismissed) {
      return;
    }
    _records[index] = current.copyWith(
      receipt: current.receipt.copyWith(userOutcome: outcome),
    );
    if (outcome == NeuraSuggestionOutcome.acted ||
        outcome == NeuraSuggestionOutcome.dismissed) {
      _nudgeSpecialistReputation(current.receipt.specialistId, outcome);
    }
    notifyListeners();
    await _persist();
    if (!_isCurrent(generation)) return;
    NeuraEventBus.I.emit(
      NeuraIntelligenceOutcomeEvent(
        receiptId: receiptId,
        outcome: outcome.name,
      ),
    );
    await _appendTimeline('intelligence_outcome', _records[index].receipt);
  }

  /// Nudges a specialist's learned reputation from a real user outcome. Each
  /// call first decays the current value toward neutral so stale history
  /// fades, then applies a small bounded step in the outcome's direction —
  /// never touching suggestion text or evidence, only this one number.
  void _nudgeSpecialistReputation(
    String specialistId,
    NeuraSuggestionOutcome outcome,
  ) {
    final current = _specialistReputation[specialistId] ?? 1.0;
    final decayed = current + (1.0 - current) * _reputationDecay;
    final delta = outcome == NeuraSuggestionOutcome.acted
        ? _reputationStep
        : -_reputationStep;
    _specialistReputation[specialistId] = (decayed + delta)
        .clamp(
          NeuraAutonomyKernel.minSpecialistReputation,
          NeuraAutonomyKernel.maxSpecialistReputation,
        )
        .toDouble();
  }

  bool _wasSurfaced(NeuraIntelligenceRecord item) =>
      item.receipt.userOutcome == NeuraSuggestionOutcome.shown ||
      item.receipt.userOutcome == NeuraSuggestionOutcome.acted ||
      item.receipt.userOutcome == NeuraSuggestionOutcome.dismissed;

  void _trimRecords() {
    if (_records.length > _maxReceipts) {
      _records.removeRange(0, _records.length - _maxReceipts);
    }
  }

  Future<void> _persist() {
    if (_writesSuspended) return Future<void>.value();
    final generation = _dataGeneration;
    final next = _writeQueue.then(
      (_) => _writeState(generation),
      onError: (_) => _writeState(generation),
    );
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _writeState(int generation) async {
    if (!_isCurrent(generation)) return;
    final state = <String, Object?>{
      'v': 1,
      'preferences': _preferences.toJson(),
      'records': _records.map((item) => item.toJson()).toList(growable: false),
      'specialist_reputation': _specialistReputation,
    };
    await NeuraPrefsCache.prefs.setString(_stateKey, jsonEncode(state));
    if (!_isCurrent(generation)) {
      await NeuraPrefsCache.prefs.remove(_stateKey);
    }
  }

  Future<void> _appendTimeline(
    String kind,
    NeuraDecisionReceipt receipt,
  ) async {
    try {
      await TimelineVault.instance.append(
        kind,
        source: 'intelligence_fabric',
        data: {
          'receipt_id': receipt.id,
          'capability_id': receipt.capabilityId,
          'specialist_id': receipt.specialistId,
          'decision': receipt.outcome.name,
          'user_outcome': receipt.userOutcome.name,
          'score': receipt.score,
        },
      );
    } catch (_) {
      // Audit availability must never make the app unusable.
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _writesSuspended = false;
    _dataGeneration = 0;
    _resetInMemory();
  }

  /// Drains queued preference writes, then forgets all decision receipts and
  /// cached preferences. It deliberately does not persist the defaults.
  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _dataGeneration += 1;
    try {
      await _writeQueue.timeout(const Duration(seconds: 3));
    } finally {
      _resetInMemory();
      notifyListeners();
    }
  }

  /// Allows fresh post-wipe state only after every deletion has succeeded.
  void resumeAfterDataWipe() {
    _resetInMemory();
    _writesSuspended = false;
    notifyListeners();
  }

  void _resetInMemory() {
    _preferences = const NeuraIntelligencePreferences();
    _records = [];
    _specialistReputation = {};
    _lastCouncil = const NeuraCouncilResult([]);
    _writeQueue = Future<void>.value();
    _initialized = false;
  }

  bool _isCurrent(int generation) =>
      !_writesSuspended && generation == _dataGeneration;
}

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;
