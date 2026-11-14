import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/forecast_calibration.dart';

// Mirrors rust/src/attunement/forecast_tests.rs so both ledgers keep one
// contract. Synthetic values only.

const _a = NeuraForecastSource(1);
const _b = NeuraForecastSource(2);

const _maxOpen = NeuraForecastLedger.maxOpen;
const _maxScored = NeuraForecastLedger.maxScored;
const _bins = NeuraForecastLedger.calibrationBins;
const _horizon = NeuraForecastLedger.maxHorizonSeconds;
const _retention = NeuraForecastLedger.scoreRetentionSeconds;

Matcher _fails(NeuraForecastError error) => throwsA(
      isA<NeuraForecastException>().having((e) => e.error, 'error', error),
    );

void _close(double actual, double expected) {
  expect(actual.isFinite, isTrue);
  expect((actual - expected).abs() < 1e-12, isTrue,
      reason: '$actual != $expected');
}

void _score(
  NeuraForecastLedger ledger,
  NeuraForecastSource source,
  double p,
  bool outcome,
  int now,
) {
  final id = ledger.record(
    source: source,
    probability: p,
    now: now,
    resolvesBy: now + 10,
  );
  ledger.resolve(id: id, outcome: outcome, now: now);
}

NeuraForecastId _record(
  NeuraForecastLedger ledger,
  NeuraForecastSource source,
  double p,
  int now,
  int resolvesBy,
) =>
    ledger.record(
      source: source,
      probability: p,
      now: now,
      resolvesBy: resolvesBy,
    );

int _seq(NeuraForecastId id) => NeuraForecastLedger.debugSequenceOf(id);

double _nextDown(double value) {
  final bytes = ByteData(8)..setFloat64(0, value);
  bytes.setInt64(0, bytes.getInt64(0) - 1);
  return bytes.getFloat64(0);
}

void main() {
  test('empty source has no invented measurements', () {
    final ledger = NeuraForecastLedger();
    expect(ledger.openCount, 0);
    expect(ledger.scoredCount, 0);
    expect(ledger.summary(_a), isNull);
    final bins = ledger.calibration(_a);
    expect(bins, hasLength(_bins));
    for (var index = 0; index < bins.length; index++) {
      _close(bins[index].lower, index / 10.0);
      _close(bins[index].upper, (index + 1) / 10.0);
      expect(bins[index].count, 0);
      expect(bins[index].meanProbability, isNull);
      expect(bins[index].observedFrequency, isNull);
    }
  });

  test('probabilities are rejected instead of silently clamped', () {
    final ledger = NeuraForecastLedger();
    for (final p in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -0.01,
      1.01,
    ]) {
      expect(
        () => _record(ledger, _a, p, 0, 1),
        _fails(NeuraForecastError.invalidProbability),
      );
    }
    expect(ledger.debugNextSequence, 1);
    expect(ledger.openCount, 0);
    expect(ledger.scoredCount, 0);
    _record(ledger, _a, 0.0, 0, 1);
    _record(ledger, _a, 1.0, 0, 1);
  });

  test('deadline must be future and within bounded horizon', () {
    final ledger = NeuraForecastLedger();
    for (final deadline in [9, 10, 11 + _horizon]) {
      expect(
        () => _record(ledger, _a, 0.5, 10, deadline),
        _fails(NeuraForecastError.invalidDeadline),
      );
    }
    _record(ledger, _a, 0.5, 10, 11);
    _record(ledger, _a, 0.5, 10, 10 + _horizon);
  });

  test('brier scores match binary probability arithmetic', () {
    final ledger = NeuraForecastLedger();
    final first = _record(ledger, _a, 0.8, 0, 10);
    final second = _record(ledger, _a, 0.2, 0, 10);
    _close(ledger.resolve(id: first, outcome: true, now: 1), 0.04);
    _close(ledger.resolve(id: second, outcome: true, now: 1), 0.64);
    final summary = ledger.summary(_a)!;
    expect(summary.scored, 2);
    _close(summary.meanProbability, 0.5);
    _close(summary.observedFrequency, 1.0);
    _close(summary.meanBrier, 0.34);
    _close(summary.skillAgainstHalfProbability, -0.36);
  });

  test('duplicate resolution cannot score again or change source', () {
    final ledger = NeuraForecastLedger();
    final id = _record(ledger, _a, 0.9, 0, 10);
    ledger.resolve(id: id, outcome: true, now: 1);
    expect(
      () => ledger.resolve(id: id, outcome: false, now: 1),
      _fails(NeuraForecastError.unknownForecast),
    );
    expect(ledger.scoredCount, 1);
    expect(ledger.summary(_a)!.scored, 1);
    expect(ledger.summary(_b), isNull);
    final other = _record(ledger, _b, 0.1, 1, 10);
    expect(other, isNot(id));
    ledger.resolve(id: other, outcome: false, now: 1);
    expect(ledger.summary(_a)!.scored, 1);
    expect(ledger.summary(_b)!.scored, 1);
  });

  test('foreign ledger id cannot resolve a matching sequence', () {
    final first = NeuraForecastLedger();
    final second = NeuraForecastLedger();
    final firstId = _record(first, _a, 0.9, 0, 10);
    final secondId = _record(second, _a, 0.9, 0, 10);
    expect(_seq(firstId), _seq(secondId));
    expect(firstId, isNot(secondId));
    expect(
      () => second.resolve(id: firstId, outcome: true, now: 1),
      _fails(NeuraForecastError.unknownForecast),
    );
    expect(second.openCount, 1);
    expect(second.scoredCount, 0);
    second.resolve(id: secondId, outcome: true, now: 1);
    first.resolve(id: firstId, outcome: true, now: 1);
  });

  test('exact deadline and late resolution expire without prior sweep', () {
    final ledger = NeuraForecastLedger();
    final before = _record(ledger, _a, 0.5, 0, 10);
    final at = _record(ledger, _a, 0.5, 0, 10);
    final after = _record(ledger, _a, 0.5, 0, 12);
    ledger.resolve(id: before, outcome: true, now: 9);
    expect(
      () => ledger.resolve(id: at, outcome: true, now: 10),
      _fails(NeuraForecastError.unknownForecast),
    );
    expect(
      () => ledger.resolve(id: after, outcome: false, now: 13),
      _fails(NeuraForecastError.unknownForecast),
    );
    expect(ledger.openCount, 0);
    expect(ledger.scoredCount, 1);
    _close(ledger.summary(_a)!.observedFrequency, 1.0);
  });

  test('backward timestamps change neither records nor watermarks', () {
    final ledger = NeuraForecastLedger();
    final id = _record(ledger, _a, 0.8, 10, 20);
    final next = ledger.debugNextSequence;
    expect(
      () => ledger.advance(9),
      _fails(NeuraForecastError.clockWentBackwards),
    );
    expect(
      () => ledger.resolve(id: id, outcome: true, now: 9),
      _fails(NeuraForecastError.clockWentBackwards),
    );
    expect(
      () => _record(ledger, _b, 0.2, 9, 30),
      _fails(NeuraForecastError.clockWentBackwards),
    );
    expect(ledger.debugLastTime, 10);
    expect(ledger.debugNextSequence, next);
    expect(ledger.openCount, 1);
    expect(ledger.scoredCount, 0);
    ledger.resolve(id: id, outcome: true, now: 10);
  });

  test('failed requests still observe time and expire records', () {
    final ledger = NeuraForecastLedger();
    final id = _record(ledger, _a, 0.5, 0, 10);
    expect(
      () => _record(ledger, _b, double.nan, 10, 20),
      _fails(NeuraForecastError.invalidProbability),
    );
    expect(ledger.openCount, 0);
    expect(ledger.debugLastTime, 10);
    expect(
      () => ledger.resolve(id: id, outcome: true, now: 9),
      _fails(NeuraForecastError.clockWentBackwards),
    );
    expect(
      () => ledger.resolve(id: id, outcome: true, now: 15),
      _fails(NeuraForecastError.unknownForecast),
    );
    expect(ledger.debugLastTime, 15);
    expect(ledger.scoredCount, 0);
  });

  test(
      'full open capacity rejects without evicting live work or consuming '
      'an id', () {
    final ledger = NeuraForecastLedger();
    final first = _record(ledger, _a, 0.5, 0, 100);
    for (var i = 1; i < _maxOpen; i++) {
      _record(ledger, _a, 0.5, 0, 100);
    }
    final next = ledger.debugNextSequence;
    expect(
      () => _record(ledger, _b, 0.5, 1, 100),
      _fails(NeuraForecastError.openCapacity),
    );
    expect(ledger.debugNextSequence, next);
    expect(ledger.openCount, _maxOpen);
    ledger.resolve(id: first, outcome: true, now: 1);
    _record(ledger, _b, 0.5, 1, 100);
    expect(ledger.openCount, _maxOpen);
  });

  test('admission clears expired open capacity without scoring it', () {
    final ledger = NeuraForecastLedger();
    final old = _record(ledger, _a, 0.5, 0, 1);
    for (var i = 1; i < _maxOpen; i++) {
      _record(ledger, _a, 0.5, 0, 1);
    }
    _record(ledger, _b, 0.2, 1, 2);
    expect(ledger.openCount, 1);
    expect(ledger.scoredCount, 0);
    expect(
      () => ledger.resolve(id: old, outcome: true, now: 1),
      _fails(NeuraForecastError.unknownForecast),
    );
  });

  test('oldest score eviction does not permit replay', () {
    final ledger = NeuraForecastLedger();
    final old = _record(ledger, _a, 1.0, 0, 10);
    ledger.resolve(id: old, outcome: false, now: 0);
    for (var i = 0; i < _maxScored; i++) {
      _score(ledger, _b, 1.0, true, 0);
    }
    expect(ledger.scoredCount, _maxScored);
    expect(ledger.summary(_a), isNull);
    _close(ledger.summary(_b)!.meanBrier, 0.0);
    expect(
      () => ledger.resolve(id: old, outcome: true, now: 0),
      _fails(NeuraForecastError.unknownForecast),
    );
    expect(ledger.scoredCount, _maxScored);
  });

  test('score age expiry is exact and does not become a false outcome', () {
    final ledger = NeuraForecastLedger();
    _score(ledger, _a, 0.8, true, 10);
    _score(ledger, _b, 0.2, false, 11);
    expect(
      ledger.advance(10 + _retention - 1),
      const NeuraForecastRemoved(open: 0, scored: 0),
    );
    expect(ledger.scoredCount, 2);
    expect(
      ledger.advance(10 + _retention),
      const NeuraForecastRemoved(open: 0, scored: 1),
    );
    expect(ledger.summary(_a), isNull);
    _close(ledger.summary(_b)!.observedFrequency, 0.0);
    expect(
      ledger.advance(11 + _retention),
      const NeuraForecastRemoved(open: 0, scored: 1),
    );
    expect(ledger.scoredCount, 0);
  });

  test('forgetting one source preserves others and never reuses ids', () {
    final ledger = NeuraForecastLedger();
    _score(ledger, _a, 0.8, true, 0);
    _score(ledger, _b, 0.2, false, 0);
    final old = _record(ledger, _a, 0.5, 0, 10);
    final retained = _record(ledger, _b, 0.5, 0, 10);
    expect(
      ledger.forgetSource(_a),
      const NeuraForecastRemoved(open: 1, scored: 1),
    );
    expect(
      ledger.forgetSource(_a),
      const NeuraForecastRemoved(open: 0, scored: 0),
    );
    expect(ledger.summary(_a), isNull);
    expect(ledger.summary(_b)!.scored, 1);
    final fresh = _record(ledger, _a, 0.7, 0, 10);
    expect(fresh, isNot(old));
    expect(_seq(fresh), greaterThan(_seq(retained)));
    expect(
      () => ledger.resolve(id: old, outcome: true, now: 0),
      _fails(NeuraForecastError.unknownForecast),
    );
    ledger.resolve(id: retained, outcome: true, now: 0);
    ledger.resolve(id: fresh, outcome: true, now: 0);
  });

  test('clear revokes handles but preserves clock and sequence', () {
    final ledger = NeuraForecastLedger();
    _score(ledger, _a, 0.8, true, 10);
    final old = _record(ledger, _a, 0.5, 10, 20);
    expect(ledger.clear(), const NeuraForecastRemoved(open: 1, scored: 1));
    expect(ledger.clear(), const NeuraForecastRemoved(open: 0, scored: 0));
    expect(
      () => ledger.advance(9),
      _fails(NeuraForecastError.clockWentBackwards),
    );
    final fresh = _record(ledger, _b, 0.5, 10, 20);
    expect(fresh, isNot(old));
    expect(_seq(fresh), _seq(old) + 1);
    expect(
      () => ledger.resolve(id: old, outcome: true, now: 10),
      _fails(NeuraForecastError.unknownForecast),
    );
    ledger.resolve(id: fresh, outcome: true, now: 10);
  });

  test('sequence exhaustion never wraps even after clear', () {
    final ledger = NeuraForecastLedger();
    ledger.debugNextSequence = NeuraForecastLedger.debugMaxIdentifier;
    final last = _record(ledger, _a, 0.5, 0, 10);
    expect(_seq(last), NeuraForecastLedger.debugMaxIdentifier);
    expect(ledger.debugNextSequence, isNull);
    expect(
      () => _record(ledger, _a, 0.5, 0, 10),
      _fails(NeuraForecastError.identifierExhausted),
    );
    ledger.clear();
    expect(
      () => _record(ledger, _a, 0.5, 0, 10),
      _fails(NeuraForecastError.identifierExhausted),
    );
    expect(ledger.openCount, 0);
  });

  test('ledger identity exhaustion is fail closed', () {
    const max = NeuraForecastLedger.debugMaxIdentifier;
    final allocation = NeuraForecastLedger.allocateLedgerIdFrom(max - 1);
    expect(allocation.id, max - 1);
    expect(allocation.next, max);
    expect(
      () => NeuraForecastLedger.allocateLedgerIdFrom(allocation.next),
      _fails(NeuraForecastError.identifierExhausted),
    );
  });

  test('calibration uses exact half-open boundaries and includes one', () {
    final ledger = NeuraForecastLedger();
    for (var index = 0; index <= _bins; index++) {
      _score(ledger, _a, index / 10.0, index.isEven, 0);
    }
    final bins = ledger.calibration(_a);
    for (final bin in bins.take(_bins - 1)) {
      expect(bin.count, 1);
      _close(bin.meanProbability!, bin.lower);
    }
    expect(bins[9].count, 2);
    _close(bins[9].meanProbability!, 0.95);
    _close(bins[9].observedFrequency!, 0.5);
    expect(bins.fold<int>(0, (sum, bin) => sum + bin.count), 11);
  });

  test('probabilities immediately below boundaries stay in previous bin', () {
    final ledger = NeuraForecastLedger();
    for (var index = 1; index < _bins; index++) {
      final boundary = index / _bins;
      _score(ledger, _a, _nextDown(boundary), false, 0);
    }
    final bins = ledger.calibration(_a);
    for (final bin in bins.take(_bins - 1)) {
      expect(bin.count, 1);
      expect(bin.meanProbability!, lessThan(bin.upper));
    }
    expect(bins[9].count, 0);
  });

  test('empirical calibration and half-probability skill are distinct', () {
    final ledger = NeuraForecastLedger();
    // Exactly calibrated at 0.5, but no skill relative to constant 0.5.
    for (var index = 0; index < 20; index++) {
      _score(ledger, _a, 0.5, index.isEven, 0);
    }
    var bin = ledger.calibration(_a)[5];
    _close(bin.meanProbability!, 0.5);
    _close(bin.observedFrequency!, 0.5);
    _close(ledger.summary(_a)!.skillAgainstHalfProbability, 0.0);

    // Beats constant 0.5 here, yet predicted 0.1 differs from observed 0.0.
    for (var index = 0; index < 20; index++) {
      _score(ledger, _b, 0.1, false, 0);
    }
    bin = ledger.calibration(_b)[1];
    _close(bin.meanProbability!, 0.1);
    _close(bin.observedFrequency!, 0.0);
    _close(ledger.summary(_b)!.skillAgainstHalfProbability, 0.96);
  });

  test('summary bounds hold at perfect and worst predictions', () {
    final ledger = NeuraForecastLedger();
    _score(ledger, _a, 0.0, false, 0);
    _score(ledger, _a, 1.0, true, 0);
    _score(ledger, _b, 0.0, true, 0);
    _score(ledger, _b, 1.0, false, 0);
    _close(ledger.summary(_a)!.meanBrier, 0.0);
    _close(ledger.summary(_a)!.skillAgainstHalfProbability, 1.0);
    _close(ledger.summary(_b)!.meanBrier, 1.0);
    _close(ledger.summary(_b)!.skillAgainstHalfProbability, -3.0);
  });

  test('mixed synthetic history preserves bounds and source isolation', () {
    final ledger = NeuraForecastLedger();
    for (var step = 0; step < _maxScored * 2; step++) {
      final now = step;
      final source = NeuraForecastSource(step % 4);
      final p = (step % 101) / 100.0;
      final id = _record(ledger, source, p, now, now + 2);
      if (step % 3 != 0) {
        final brier = ledger.resolve(id: id, outcome: step.isEven, now: now);
        expect(brier, inInclusiveRange(0.0, 1.0));
        expect(
          () => ledger.resolve(id: id, outcome: false, now: now),
          _fails(NeuraForecastError.unknownForecast),
        );
      }
      if (step % 113 == 0) {
        ledger.forgetSource(NeuraForecastSource((step + 1) % 4));
      }
      if (step % 997 == 0) {
        ledger.clear();
      }
      expect(ledger.openCount, lessThanOrEqualTo(_maxOpen));
      expect(ledger.scoredCount, lessThanOrEqualTo(_maxScored));
      expect(ledger.debugOpenDeadlines.every((d) => d > now), isTrue);
    }
    var total = 0;
    for (final source in const [
      NeuraForecastSource(0),
      _a,
      _b,
      NeuraForecastSource(3),
    ]) {
      final bins = ledger.calibration(source);
      final binned = bins.fold<int>(0, (sum, bin) => sum + bin.count);
      final summary = ledger.summary(source);
      expect(summary?.scored ?? 0, binned);
      if (summary != null) {
        expect(summary.meanBrier, inInclusiveRange(0.0, 1.0));
        expect(summary.skillAgainstHalfProbability, inInclusiveRange(-3, 1));
        total += summary.scored;
      }
      for (final bin in bins.where((bin) => bin.count > 0)) {
        expect(bin.meanProbability!, inInclusiveRange(0.0, 1.0));
        expect(bin.observedFrequency!, inInclusiveRange(0.0, 1.0));
      }
    }
    expect(total, ledger.scoredCount);
  });

  test('handles do not reveal ledger or sequence numbers', () {
    final ledger = NeuraForecastLedger();
    final id = _record(ledger, _a, 0.5, 0, 10);
    expect(id.toString(), 'NeuraForecastId(opaque)');
  });
}
