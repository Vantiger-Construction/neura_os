import 'forecast_calibration.dart';
import 'models.dart';

/// Fixed registry of suggestion specialists whose cards may be calibrated.
///
/// Source numbers are stable application constants, never derived from user
/// data. A specialist that is not listed here is never forecast. Care
/// support is deliberately absent: whether someone accepts a care card is not
/// a measure of whether offering it was right, and it must never look like
/// an engagement target. See `docs/SUGGESTION_CALIBRATION_INTEGRATION.md`.
class NeuraCalibrationSources {
  const NeuraCalibrationSources._();

  static const Map<String, ({int id, String label})> _registry = {
    'initiative.arrival': (id: 1, label: 'Welcome back'),
    'initiative.routine_shift': (id: 2, label: 'Late-night check-in'),
    'opportunity_radar.mood_reset': (id: 10, label: 'Mood reset'),
    'opportunity_radar.dream_pattern_check': (id: 11, label: 'Dream patterns'),
    'opportunity_radar.quest_micro_step': (id: 12, label: 'Quest steps'),
    'opportunity_radar.focus_sprint': (id: 13, label: 'Focus sprints'),
    'opportunity_radar.goal_to_quest': (id: 14, label: 'Goal to quest'),
    'joy_specialist': (id: 20, label: 'Joy moments'),
    'relationship_specialist': (id: 21, label: 'Relationship check-ins'),
  };

  /// Specialists that are never calibrated, kept explicit so a later
  /// registry edit has to remove them from here first.
  static const Set<String> excluded = {'opportunity_radar.care_support'};

  static Iterable<String> get specialistIds => _registry.keys;

  static NeuraForecastSource? sourceFor(String specialistId) {
    if (excluded.contains(specialistId)) return null;
    final entry = _registry[specialistId];
    return entry == null ? null : NeuraForecastSource(entry.id);
  }

  static String? labelFor(String specialistId) =>
      excluded.contains(specialistId) ? null : _registry[specialistId]?.label;
}

/// Display-only statistics for one suggestion source.
class NeuraSuggestionCalibrationEntry {
  const NeuraSuggestionCalibrationEntry({
    required this.specialistId,
    required this.label,
    required this.summary,
  });

  final String specialistId;
  final String label;
  final NeuraForecastSummary summary;
}

/// Measures how well the Autonomy Kernel's score for a shown suggestion
/// matched whether the user accepted it.
///
/// Event definition: a card that reached a rendered frame is accepted
/// ("acted") strictly before the card's own expiry. A dismissal resolves the
/// forecast as not accepted. A card that expires without a gesture, or whose
/// gesture arrives at or after expiry, is dropped unscored; it is never
/// counted as a rejection.
///
/// The forecast probability is the kernel's decision-receipt score. That
/// score was not designed as a probability, which is precisely what this
/// measures. Results are display-only: nothing here feeds the kernel,
/// specialist reputation, caps or any other decision.
///
/// The ledger is in memory only and is cleared whenever proactive
/// suggestions, local learning or the Safe Mode gate stops allowing it,
/// when decision history is cleared, and on data wipe.
class NeuraSuggestionCalibration {
  NeuraSuggestionCalibration({required bool Function() allowed})
      : _allowed = allowed;

  /// Bounds for receipt bookkeeping. Offers mirror the controller's receipt
  /// history; open handles mirror the ledger's own open capacity.
  static const int maxOffers = 100;
  static const int maxOpenHandles = NeuraForecastLedger.maxOpen;

  final bool Function() _allowed;
  final NeuraForecastLedger _ledger = NeuraForecastLedger();
  // Map literals keep insertion order, so the first key is the oldest.
  final Map<String, DateTime> _offers = <String, DateTime>{};
  final Map<String, NeuraForecastId> _open = <String, NeuraForecastId>{};

  /// Remembers the expiry of a candidate the kernel allowed, keyed by its
  /// receipt. Only offered receipts can later become forecasts.
  void offered({required String receiptId, required DateTime expiresAt}) {
    if (!_enforceGate()) return;
    _offers.remove(receiptId);
    _offers[receiptId] = expiresAt;
    while (_offers.length > maxOffers) {
      _offers.remove(_offers.keys.first);
    }
  }

  /// Records one forecast when a card first reaches a rendered frame.
  void shown({required NeuraDecisionReceipt receipt, required DateTime now}) {
    if (!_enforceGate()) return;
    if (!receipt.isVisible || _open.containsKey(receipt.id)) return;
    final source = NeuraCalibrationSources.sourceFor(receipt.specialistId);
    final expiresAt = _offers.remove(receipt.id);
    if (source == null || expiresAt == null) return;
    try {
      final id = _ledger.record(
        source: source,
        probability: receipt.score,
        now: _seconds(now),
        resolvesBy: _seconds(expiresAt),
      );
      _open[receipt.id] = id;
      while (_open.length > maxOpenHandles) {
        _open.remove(_open.keys.first);
      }
    } on NeuraForecastException {
      // Fail closed: an invalid score, deadline, capacity or clock rollback
      // simply leaves this card unmeasured.
    }
  }

  /// Resolves the card's forecast from a real user gesture.
  void resolved({
    required String receiptId,
    required bool acted,
    required DateTime now,
  }) {
    if (!_enforceGate()) return;
    final id = _open.remove(receiptId);
    if (id == null) return;
    try {
      _ledger.resolve(id: id, outcome: acted, now: _seconds(now));
    } on NeuraForecastException {
      // Late, unknown or clock-rollback resolutions stay unscored.
    }
  }

  /// Retained statistics for registered sources that have any, as of [now].
  List<NeuraSuggestionCalibrationEntry> entries({required DateTime now}) {
    if (!_enforceGate()) return const [];
    try {
      _ledger.advance(_seconds(now));
    } on NeuraForecastException {
      // Clock rollback: show the last accepted state rather than nothing.
    }
    final entries = <NeuraSuggestionCalibrationEntry>[];
    for (final specialistId in NeuraCalibrationSources.specialistIds) {
      final source = NeuraCalibrationSources.sourceFor(specialistId);
      final label = NeuraCalibrationSources.labelFor(specialistId);
      if (source == null || label == null) continue;
      final summary = _ledger.summary(source);
      if (summary == null) continue;
      entries.add(
        NeuraSuggestionCalibrationEntry(
          specialistId: specialistId,
          label: label,
          summary: summary,
        ),
      );
    }
    return List.unmodifiable(entries);
  }

  /// Forget every measurement and pending forecast. Identifier and clock
  /// watermarks are kept so cleared handles can never be replayed.
  void clear() {
    _ledger.clear();
    _offers.clear();
    _open.clear();
  }

  bool _enforceGate() {
    if (_allowed()) return true;
    if (_ledger.openCount != 0 ||
        _ledger.scoredCount != 0 ||
        _offers.isNotEmpty ||
        _open.isNotEmpty) {
      clear();
    }
    return false;
  }

  static int _seconds(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
