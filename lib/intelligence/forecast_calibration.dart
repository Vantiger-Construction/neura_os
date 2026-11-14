import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Bounded, in-memory scoring of binary forecasts.
///
/// A Dart port of the contract in `rust/src/attunement/forecast.rs` (see
/// `docs/FORECAST_CALIBRATION_FOUNDATION.md`). The Rust library is only loaded
/// by the Windows cloud swarm after a fresh approval, so local, all-platform
/// suggestion calibration uses this port instead. Behaviour, limits and
/// error cases match the Rust ledger; its tests are mirrored in
/// `test/intelligence/forecast_calibration_test.dart`.
///
/// Forecasts are immutable after admission. Opaque identifiers are unique
/// within this isolate; neither clearing nor forgetting reuses them. They are
/// not durable IDs or authorization tokens, and the ledger is never
/// persisted. See `docs/SUGGESTION_CALIBRATION_INTEGRATION.md` for how the
/// suggestion pipeline is allowed to use it.
class NeuraForecastLedger {
  NeuraForecastLedger() : _ledgerId = _allocateLedgerId();

  static const int maxOpen = 256;
  static const int maxScored = 2000;
  static const int calibrationBins = 10;
  static const int maxHorizonSeconds = 7 * 86400;
  static const int scoreRetentionSeconds = 90 * 86400;

  /// Brier score of predicting exactly 0.5, regardless of outcome prevalence.
  static const double halfProbabilityBrier = 0.25;

  /// Largest integer every Dart target (including the web) represents exactly.
  /// Identifier allocation fails at this bound instead of wrapping.
  static const int _maxIdentifier = 9007199254740991;

  static int _nextLedgerId = 1;

  final int _ledgerId;
  int? _nextSequence = 1;
  int? _lastTime;
  final List<_OpenForecast> _open = <_OpenForecast>[];
  final ListQueue<_ScoredForecast> _scored = ListQueue<_ScoredForecast>();

  int get openCount => _open.length;
  int get scoredCount => _scored.length;

  @visibleForTesting
  int? get debugNextSequence => _nextSequence;

  @visibleForTesting
  set debugNextSequence(int? value) => _nextSequence = value;

  @visibleForTesting
  int? get debugLastTime => _lastTime;

  @visibleForTesting
  Iterable<int> get debugOpenDeadlines =>
      _open.map((forecast) => forecast.resolvesBy);

  @visibleForTesting
  static int debugSequenceOf(NeuraForecastId id) => id._sequence;

  /// Admit a finite probability in [0, 1]. The deadline must be strictly
  /// after [now] and at most seven days ahead. Open capacity rejects new work;
  /// it never silently replaces or evicts another live forecast.
  ///
  /// Throws [NeuraForecastException]. Clock maintenance has already run when
  /// a later validation step fails, exactly as in the Rust ledger.
  NeuraForecastId record({
    required NeuraForecastSource source,
    required double probability,
    required int now,
    required int resolvesBy,
  }) {
    advance(now);
    if (!probability.isFinite || probability < 0 || probability > 1) {
      throw const NeuraForecastException(
        NeuraForecastError.invalidProbability,
      );
    }
    final horizon = resolvesBy - now;
    if (resolvesBy < now || horizon < 1 || horizon > maxHorizonSeconds) {
      throw const NeuraForecastException(NeuraForecastError.invalidDeadline);
    }
    if (_open.length == maxOpen) {
      throw const NeuraForecastException(NeuraForecastError.openCapacity);
    }
    final sequence = _nextSequence;
    if (sequence == null) {
      throw const NeuraForecastException(
        NeuraForecastError.identifierExhausted,
      );
    }
    final id = NeuraForecastId._(_ledgerId, sequence);
    _nextSequence = sequence >= _maxIdentifier ? null : sequence + 1;
    _open.add(
      _OpenForecast(
        id: id,
        source: source,
        probability: probability,
        resolvesBy: resolvesBy,
      ),
    );
    return id;
  }

  /// Score once, only strictly before the deadline. The source and
  /// probability are those admitted by [record]; resolution cannot replace
  /// either one. Late outcomes are dropped unscored, including at the exact
  /// deadline. Returns the Brier score of the resolved forecast.
  double resolve({
    required NeuraForecastId id,
    required bool outcome,
    required int now,
  }) {
    advance(now);
    final index = _open.indexWhere((forecast) => forecast.id == id);
    if (index < 0) {
      throw const NeuraForecastException(NeuraForecastError.unknownForecast);
    }
    final forecast = _open.removeAt(index);
    final brier = _brierScore(forecast.probability, outcome);
    if (_scored.length == maxScored) {
      _scored.removeFirst();
    }
    _scored.addLast(
      _ScoredForecast(
        source: forecast.source,
        probability: forecast.probability,
        outcome: outcome,
        resolvedAt: now,
      ),
    );
    return brier;
  }

  /// Expire open entries at their deadline and scores at age 90 days.
  /// Expiry is logical time maintenance, not a background timer or secure
  /// erase. A backward timestamp throws without changing anything.
  NeuraForecastRemoved advance(int now) {
    final previous = _lastTime;
    if (previous != null && now < previous) {
      throw const NeuraForecastException(
        NeuraForecastError.clockWentBackwards,
      );
    }
    _lastTime = now;
    final openBefore = _open.length;
    final scoredBefore = _scored.length;
    _open.removeWhere((forecast) => now >= forecast.resolvesBy);
    _scored.removeWhere(
      (forecast) => now - forecast.resolvedAt >= scoreRetentionSeconds,
    );
    return NeuraForecastRemoved(
      open: openBefore - _open.length,
      scored: scoredBefore - _scored.length,
    );
  }

  /// Remove a source's logical records. Does not reuse IDs or reset the
  /// clock.
  NeuraForecastRemoved forgetSource(NeuraForecastSource source) {
    final openBefore = _open.length;
    final scoredBefore = _scored.length;
    _open.removeWhere((forecast) => forecast.source == source);
    _scored.removeWhere((forecast) => forecast.source == source);
    return NeuraForecastRemoved(
      open: openBefore - _open.length,
      scored: scoredBefore - _scored.length,
    );
  }

  /// Clear logical records, retaining ID and clock watermarks against replay.
  NeuraForecastRemoved clear() {
    final removed = NeuraForecastRemoved(
      open: _open.length,
      scored: _scored.length,
    );
    _open.clear();
    _scored.clear();
    return removed;
  }

  /// Summarize retained outcomes only. Unresolved and expired predictions are
  /// not evidence of false outcomes. Null means no retained observations.
  NeuraForecastSummary? summary(NeuraForecastSource source) {
    var scored = 0;
    var probabilities = 0.0;
    var outcomes = 0;
    var briers = 0.0;
    for (final forecast in _scored) {
      if (forecast.source != source) continue;
      scored += 1;
      probabilities += forecast.probability;
      if (forecast.outcome) outcomes += 1;
      briers += _brierScore(forecast.probability, forecast.outcome);
    }
    if (scored == 0) return null;
    final meanBrier = briers / scored;
    return NeuraForecastSummary(
      scored: scored,
      meanProbability: probabilities / scored,
      observedFrequency: outcomes / scored,
      meanBrier: meanBrier,
      skillAgainstHalfProbability: 1.0 - meanBrier / halfProbabilityBrier,
    );
  }

  /// Empirical calibration, not a skill score or an uncertainty interval.
  /// All ten bins are returned; counts are essential when interpreting means.
  List<NeuraCalibrationBin> calibration(NeuraForecastSource source) {
    final counts = List<int>.filled(calibrationBins, 0);
    final probabilities = List<double>.filled(calibrationBins, 0);
    final outcomes = List<int>.filled(calibrationBins, 0);
    for (final forecast in _scored) {
      if (forecast.source != source) continue;
      var index = calibrationBins - 1;
      for (var bin = 0; bin < calibrationBins; bin++) {
        if (forecast.probability < (bin + 1) / calibrationBins) {
          index = bin;
          break;
        }
      }
      counts[index] += 1;
      probabilities[index] += forecast.probability;
      if (forecast.outcome) outcomes[index] += 1;
    }
    return List<NeuraCalibrationBin>.unmodifiable(
      List<NeuraCalibrationBin>.generate(calibrationBins, (index) {
        final count = counts[index];
        return NeuraCalibrationBin(
          lower: index / calibrationBins,
          upper: (index + 1) / calibrationBins,
          count: count,
          meanProbability: count == 0 ? null : probabilities[index] / count,
          observedFrequency: count == 0 ? null : outcomes[index] / count,
        );
      }),
    );
  }

  static int _allocateLedgerId() {
    final allocation = allocateLedgerIdFrom(_nextLedgerId);
    _nextLedgerId = allocation.next;
    return allocation.id;
  }

  /// Pure allocation step, exposed so tests can prove exhaustion fails
  /// closed without mutating the isolate-wide counter.
  @visibleForTesting
  static ({int id, int next}) allocateLedgerIdFrom(int next) {
    if (next >= _maxIdentifier) {
      throw const NeuraForecastException(
        NeuraForecastError.identifierExhausted,
      );
    }
    return (id: next, next: next + 1);
  }

  @visibleForTesting
  static const int debugMaxIdentifier = _maxIdentifier;

  static double _brierScore(double probability, bool outcome) {
    final target = outcome ? 1.0 : 0.0;
    final error = probability - target;
    return error * error;
  }
}

/// An application-owned source registry number, not a permission or identity
/// proof. See `NeuraCalibrationSources` for the suggestion registry.
class NeuraForecastSource {
  const NeuraForecastSource(this.value) : assert(value >= 0 && value <= 0xFFFF);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is NeuraForecastSource && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// An opaque, non-serializable handle. Only a ledger can issue one.
class NeuraForecastId {
  const NeuraForecastId._(this._ledger, this._sequence);

  final int _ledger;
  final int _sequence;

  @override
  bool operator ==(Object other) =>
      other is NeuraForecastId &&
      other._ledger == _ledger &&
      other._sequence == _sequence;

  @override
  int get hashCode => Object.hash(_ledger, _sequence);

  @override
  String toString() => 'NeuraForecastId(opaque)';
}

enum NeuraForecastError {
  clockWentBackwards,
  invalidProbability,
  invalidDeadline,
  openCapacity,
  identifierExhausted,

  /// Includes expired, resolved, forgotten, cleared and foreign-ledger IDs.
  unknownForecast,
}

class NeuraForecastException implements Exception {
  const NeuraForecastException(this.error);

  final NeuraForecastError error;

  @override
  String toString() => 'NeuraForecastException(${error.name})';
}

class NeuraForecastRemoved {
  const NeuraForecastRemoved({required this.open, required this.scored});

  final int open;
  final int scored;

  @override
  bool operator ==(Object other) =>
      other is NeuraForecastRemoved &&
      other.open == open &&
      other.scored == scored;

  @override
  int get hashCode => Object.hash(open, scored);

  @override
  String toString() => 'NeuraForecastRemoved(open: $open, scored: $scored)';
}

/// Descriptive statistics over retained, resolved forecasts for one source.
/// This is neither a confidence interval nor a recommendation to change
/// policy.
class NeuraForecastSummary {
  const NeuraForecastSummary({
    required this.scored,
    required this.meanProbability,
    required this.observedFrequency,
    required this.meanBrier,
    required this.skillAgainstHalfProbability,
  });

  final int scored;
  final double meanProbability;
  final double observedFrequency;
  final double meanBrier;

  /// `1 - meanBrier / 0.25`, in [-3, 1]. Compares only with constant 0.5,
  /// not a prevalence-adjusted baseline; it does not measure calibration.
  final double skillAgainstHalfProbability;
}

/// Equal-width bin [lower, upper), except the final bin includes 1.0.
/// Empty bins have no means, rather than an invented zero measurement.
class NeuraCalibrationBin {
  const NeuraCalibrationBin({
    required this.lower,
    required this.upper,
    required this.count,
    required this.meanProbability,
    required this.observedFrequency,
  });

  final double lower;
  final double upper;
  final int count;
  final double? meanProbability;
  final double? observedFrequency;
}

class _OpenForecast {
  const _OpenForecast({
    required this.id,
    required this.source,
    required this.probability,
    required this.resolvesBy,
  });

  final NeuraForecastId id;
  final NeuraForecastSource source;
  final double probability;
  final int resolvesBy;
}

class _ScoredForecast {
  const _ScoredForecast({
    required this.source,
    required this.probability,
    required this.outcome,
    required this.resolvedAt,
  });

  final NeuraForecastSource source;
  final double probability;
  final bool outcome;
  final int resolvedAt;
}
