import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_gesture.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/avatar/motion/neura_motion_engine.dart';

const double _frame = 1 / 60;

NeuraMotionEngine _engine({int seed = 7}) =>
    NeuraMotionEngine(random: math.Random(seed))
      ..setMotionLevel(NeuraBodyMotionLevel.expressive);

List<NeuraPose> _run(NeuraMotionEngine e, double seconds) => [
      for (var i = 0; i < (seconds / _frame).round(); i++) e.tick(_frame),
    ];

void _expectBounded(NeuraPose p) {
  expect(p.isFinite, isTrue, reason: '$p');
  expect(p.scale, inInclusiveRange(0.85, 1.2), reason: '$p');
  expect(p.squash.abs(), lessThanOrEqualTo(0.12), reason: '$p');
  expect(p.dx.abs(), lessThan(0.1), reason: '$p');
  expect(p.dy.abs(), lessThan(0.15), reason: '$p');
  expect(p.lean.abs(), lessThan(0.3), reason: '$p');
  expect(p.tilt.abs(), lessThan(0.3), reason: '$p');
  expect(p.glow, inInclusiveRange(0.0, 1.0));
}

void main() {
  test('stays finite and bounded under a randomized workout', () {
    final e = _engine();
    final rng = math.Random(42);
    for (var i = 0; i < 60 * 90; i++) {
      if (i % 37 == 0) {
        e.setPhase(NeuraBodyPhase.values[rng.nextInt(5)]);
      }
      if (i % 23 == 0) {
        e.gesture(
          NeuraGesture.values[rng.nextInt(NeuraGesture.values.length)],
          intensity: rng.nextDouble(),
        );
      }
      if (i % 51 == 0) {
        e.setMood(rng.nextDouble() * 2 - 1, rng.nextDouble());
      }
      e.setMouthOpen(rng.nextDouble());
      // Include frame hitches.
      _expectBounded(e.tick(i % 300 == 0 ? 0.5 : _frame));
    }
  });

  test('ignores non-finite inputs', () {
    final e = _engine()
      ..setMood(double.nan, double.infinity)
      ..setMouthOpen(double.nan);
    expect(e.gesture(NeuraGesture.nod, intensity: double.nan), isFalse);
    expect(e.tick(double.nan), e.pose);
    expect(e.tick(-1), e.pose);
    for (final p in _run(e, 3)) {
      _expectBounded(p);
    }
  });

  test('phase changes blend instead of jumping', () {
    final e = _engine();
    _run(e, 2);
    var prev = e.pose;
    for (final phase in [
      NeuraBodyPhase.listening,
      NeuraBodyPhase.speaking,
      NeuraBodyPhase.thinking,
      NeuraBodyPhase.error,
      NeuraBodyPhase.idle,
    ]) {
      e.setPhase(phase);
      for (final p in _run(e, 1.5)) {
        expect((p.dy - prev.dy).abs(), lessThan(0.006), reason: '$phase');
        expect((p.scale - prev.scale).abs(), lessThan(0.008), reason: '$phase');
        expect((p.lean - prev.lean).abs(), lessThan(0.02), reason: '$phase');
        prev = p;
      }
    }
  });

  test('a gesture visibly moves her body and then settles back', () {
    // Listening suppresses idle attention, isolating the gesture.
    final base = _engine(seed: 1)..setPhase(NeuraBodyPhase.listening);
    final cued = _engine(seed: 1)..setPhase(NeuraBodyPhase.listening);
    _run(base, 3);
    _run(cued, 3);
    expect(cued.gesture(NeuraGesture.bounce, intensity: 1), isTrue);

    var peak = 0.0;
    for (var i = 0; i < 60; i++) {
      final d = (cued.tick(_frame).dy - base.tick(_frame).dy).abs();
      peak = math.max(peak, d);
    }
    expect(peak, greaterThan(0.01), reason: 'bounce should lift her');

    _run(base, 3);
    _run(cued, 3);
    expect((cued.pose.dy - base.pose.dy).abs(), lessThan(0.001));
  });

  test('Safe Mode freezes to exact neutral and rejects gestures', () {
    final e = _engine();
    _run(e, 1);
    e.gesture(NeuraGesture.celebrate);
    _run(e, 0.2);
    e.setFrozen(true);
    expect(e.pose.dy, 0);
    expect(e.gesture(NeuraGesture.nod), isFalse);
    for (final p in _run(e, 2)) {
      expect(p.dx, 0);
      expect(p.dy, 0);
      expect(p.lean, 0);
      expect(p.tilt, 0);
      expect(p.scale, 1);
    }
  });

  test('Still preference rejects gestures and eases to rest', () {
    final e = _engine();
    _run(e, 2);
    e.setMotionLevel(NeuraBodyMotionLevel.still);
    expect(e.isStill, isTrue);
    expect(e.gesture(NeuraGesture.wave), isFalse);
    _run(e, 8);
    expect(e.pose.dy.abs(), lessThan(0.002));
    expect(e.pose.lean.abs(), lessThan(0.002));
    expect((e.pose.scale - 1).abs(), lessThan(0.002));
  });

  test('she acts on her own when idle', () {
    final e = _engine(seed: 3)..setMood(0.6, 0.9);
    final poses = _run(e, 45);
    double range(double Function(NeuraPose) f) {
      final v = poses.map(f);
      return v.reduce(math.max) - v.reduce(math.min);
    }

    // Her ambient breath/sway alone stays well under these; exceeding any of
    // them means she chose to glance, shift weight, stretch or hop.
    final acted = range((p) => p.tilt) > 0.03 ||
        range((p) => p.dy) > 0.025 ||
        range((p) => p.dx) > 0.015;
    expect(acted, isTrue);
  });

  test('mood shapes posture: low mood slumps, high mood lifts', () {
    double avgDy(double mood) {
      final e = _engine(seed: 5)
        ..setPhase(NeuraBodyPhase.listening)
        ..setMood(mood, 0.5);
      final poses = _run(e, 6).skip(240);
      return poses.map((p) => p.dy).reduce((a, b) => a + b) / poses.length;
    }

    expect(avgDy(-1), greaterThan(avgDy(1)));
  });

  test('presence priority matches NeuraCompanionPresence', () {
    expect(
      NeuraMotion.resolvePhase(
          error: false, listening: true, speaking: true, thinking: true),
      NeuraBodyPhase.listening,
    );
    expect(
      NeuraMotion.resolvePhase(
          error: false, listening: false, speaking: true, thinking: true),
      NeuraBodyPhase.speaking,
    );
    expect(
      NeuraMotion.resolvePhase(
          error: true, listening: true, speaking: false, thinking: false),
      NeuraBodyPhase.error,
    );
    expect(
      NeuraMotion.resolvePhase(
          error: false, listening: false, speaking: false, thinking: false),
      NeuraBodyPhase.idle,
    );
  });
}
