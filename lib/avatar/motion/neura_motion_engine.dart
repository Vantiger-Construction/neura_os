// lib/avatar/motion/neura_motion_engine.dart
//
// Fluent procedural body motion for Neura.
//
// Why this exists: every avatar surface used to own its own `sin()` transform
// that snapped on/off when state changed. Nothing blended, so she read as a
// sticker being wiggled. This engine gives her one continuous body:
//
//   state + mood + energy + room stance + her own idle attention + gestures
//        └────────────── summed into per-channel TARGETS ──────────────┘
//                                   │
//                   critically-ish damped springs (per channel)
//                                   │
//                    + continuous breath & sway oscillators
//                                   │
//                               NeuraPose  → renderer (Transform)
//
// Springs mean any change — a new phase, a mood shift from the brain, a nod —
// is followed smoothly with natural overshoot/settle instead of a jump.
//
// Pure Dart (no Flutter) so it can be unit-tested and reused by the mascot
// isolate. Safety: Safe Mode / reduced motion / "Still" freeze to neutral and
// suppress all gestures and idle behaviour.

import 'dart:math' as math;

import 'neura_gesture.dart';

/// Activity phase the body is expressing.
enum NeuraBodyPhase { idle, listening, thinking, speaking, error }

/// Global amplitude preference (mirrors NeuraCompanionMotion).
enum NeuraBodyMotionLevel { still, subtle, expressive }

/// Room stance (mirrors NeuraRoomStance) — biases resting posture.
enum NeuraBodyStance {
  welcoming,
  reflective,
  playful,
  grounding,
  dreaming,
  guardian,
}

/// Output pose. All offsets are *fractions of the avatar's box size* so the
/// same pose works for a 60px chip and a 400px mascot.
class NeuraPose {
  const NeuraPose({
    this.dx = 0,
    this.dy = 0,
    this.lean = 0,
    this.tilt = 0,
    this.scale = 1,
    this.squash = 0,
    this.glow = 0.15,
    this.warmth = 0,
  });

  /// Horizontal offset (fraction of width, + = right).
  final double dx;

  /// Vertical offset (fraction of height, + = down).
  final double dy;

  /// Whole-body rotation about the FEET, radians (+ = clockwise / lean right).
  final double lean;

  /// Upper-body / head rotation about the CENTER, radians.
  final double tilt;

  /// Uniform scale about the feet.
  final double scale;

  /// Vertical stretch (+) / squash (−) about the feet; width counter-scales
  /// slightly to preserve volume.
  final double squash;

  /// Aura intensity 0..1.
  final double glow;

  /// Aura colour bias −1 (cool) .. 1 (warm). Mirrors mood.
  final double warmth;

  static const NeuraPose neutral = NeuraPose();

  bool get isFinite =>
      dx.isFinite &&
      dy.isFinite &&
      lean.isFinite &&
      tilt.isFinite &&
      scale.isFinite &&
      squash.isFinite &&
      glow.isFinite &&
      warmth.isFinite;

  @override
  String toString() => 'NeuraPose(dx:${dx.toStringAsFixed(4)} '
      'dy:${dy.toStringAsFixed(4)} lean:${lean.toStringAsFixed(4)} '
      'tilt:${tilt.toStringAsFixed(4)} scale:${scale.toStringAsFixed(4)} '
      'squash:${squash.toStringAsFixed(4)} glow:${glow.toStringAsFixed(3)})';
}

/// Damped harmonic spring for one channel.
class _Spring {
  _Spring(this.value, {required this.hz, required this.damping})
      : target = value;

  double value;
  double velocity = 0;
  double target;

  /// Natural frequency (Hz). Higher = snappier.
  final double hz;

  /// Damping ratio. 1 = critical (no overshoot); <1 = lively overshoot.
  final double damping;

  void step(double dt) {
    final w = 2 * math.pi * hz;
    // Semi-implicit Euler is stable for w*dt < ~1; callers sub-step.
    final accel = -2 * damping * w * velocity - w * w * (value - target);
    velocity += accel * dt;
    value += velocity * dt;
  }

  void snap(double v) {
    value = v;
    target = v;
    velocity = 0;
  }
}

class _ActiveGesture {
  _ActiveGesture(this.gesture, this.intensity, this.duration);
  final NeuraGesture gesture;
  final double intensity;
  final double duration;
  double t = 0; // seconds elapsed
  double get u => (t / duration).clamp(0.0, 1.0);
  bool get done => t >= duration;
}

/// Additive offsets a gesture contributes to channel targets.
class _Offsets {
  double dx = 0, dy = 0, lean = 0, tilt = 0, scale = 0, squash = 0, glow = 0;
  double breath = 0; // extra breath amplitude
}

class NeuraMotionEngine {
  NeuraMotionEngine({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;

  // ── Inputs (set by drivers) ───────────────────────────────────────────────
  NeuraBodyPhase _phase = NeuraBodyPhase.idle;
  NeuraBodyMotionLevel _level = NeuraBodyMotionLevel.subtle;
  NeuraBodyStance _stance = NeuraBodyStance.welcoming;
  double _mood = 0; // −1..1
  double _energy = 0.5; // 0..1
  double _mouthOpen = 0; // 0..1 (from viseme/TTS)
  bool _frozen = false; // safe mode / reduced motion

  NeuraBodyPhase get phase => _phase;
  NeuraBodyMotionLevel get level => _level;
  double get mood => _mood;
  double get energy => _energy;
  bool get isStill => _frozen || _level == NeuraBodyMotionLevel.still;

  // ── Springs ───────────────────────────────────────────────────────────────
  // Posture channels are softer; gesture-heavy channels are snappier.
  final _dx = _Spring(0, hz: 2.2, damping: 0.78);
  final _dy = _Spring(0, hz: 3.0, damping: 0.62);
  final _lean = _Spring(0, hz: 1.8, damping: 0.8);
  final _tilt = _Spring(0, hz: 2.8, damping: 0.6);
  final _scale = _Spring(1, hz: 2.6, damping: 0.7);
  final _squash = _Spring(0, hz: 5.0, damping: 0.45);
  final _glow = _Spring(0.15, hz: 1.2, damping: 1.0);
  final _warmth = _Spring(0, hz: 0.6, damping: 1.0);
  // Oscillator parameters are springs too, so rate/amplitude changes blend.
  final _breathRate = _Spring(0.22, hz: 0.5, damping: 1.0);
  final _breathAmp = _Spring(1.0, hz: 0.8, damping: 1.0);
  final _swayAmp = _Spring(1.0, hz: 0.6, damping: 1.0);
  final _amp = _Spring(0.6, hz: 0.7, damping: 1.0); // motion-level master

  late final List<_Spring> _all = [
    _dx,
    _dy,
    _lean,
    _tilt,
    _scale,
    _squash,
    _glow,
    _warmth,
    _breathRate,
    _breathAmp,
    _swayAmp,
    _amp,
  ];

  double _breathPhase = 0;
  double _clock = 0;

  // Persistent weight shift chosen by her idle attention.
  double _weightTarget = 0;

  final List<_ActiveGesture> _gestures = [];
  double _nextIdleAt = 3.0;
  double _lastGestureAt = -100;

  NeuraPose _pose = NeuraPose.neutral;
  NeuraPose get pose => _pose;

  // ── Input API ─────────────────────────────────────────────────────────────

  void setPhase(NeuraBodyPhase next) {
    if (next == _phase) return;
    final prev = _phase;
    _phase = next;
    if (isStill) return;
    // Transition flourishes — the body *reacts* to state changes.
    if (next == NeuraBodyPhase.listening && prev == NeuraBodyPhase.idle) {
      _start(NeuraGesture.leanIn, 0.45);
    } else if (next == NeuraBodyPhase.error) {
      _start(NeuraGesture.shake, 0.5);
    } else if (next == NeuraBodyPhase.idle && prev == NeuraBodyPhase.speaking) {
      _start(NeuraGesture.settle, 0.5);
    }
    _scheduleIdle(min: 2.5);
  }

  void setMotionLevel(NeuraBodyMotionLevel level) {
    _level = level;
    if (isStill) _gestures.clear();
  }

  void setStance(NeuraBodyStance stance) => _stance = stance;

  void setMood(double mood, double energy) {
    _mood = mood.isFinite ? mood.clamp(-1.0, 1.0) : 0;
    _energy = energy.isFinite ? energy.clamp(0.0, 1.0) : 0.5;
  }

  void setMouthOpen(double open) =>
      _mouthOpen = open.isFinite ? open.clamp(0.0, 1.0) : 0;

  /// Safe Mode / OS reduced-motion. Freezing snaps to neutral immediately —
  /// no spring-out, so nothing "moves" after the user asked it to stop.
  void setFrozen(bool frozen) {
    if (frozen == _frozen) return;
    _frozen = frozen;
    if (frozen) {
      _gestures.clear();
      for (final s in _all) {
        s.snap(
          s == _scale
              ? 1
              : s == _glow
                  ? 0.15
                  : s == _breathRate
                      ? 0.22
                      : (s == _breathAmp || s == _swayAmp)
                          ? 1
                          : s == _amp
                              ? 0
                              : 0,
        );
      }
      _weightTarget = 0;
      _pose = NeuraPose.neutral;
    }
  }

  /// Request a gesture. Returns false if suppressed (still / frozen / full).
  bool gesture(NeuraGesture g, {double intensity = 0.7}) {
    if (isStill) return false;
    if (!intensity.isFinite) return false;
    return _start(g, intensity.clamp(0.0, 1.0));
  }

  // ── Simulation ────────────────────────────────────────────────────────────

  /// Advance by [dt] seconds and return the new pose. Safe to call with any
  /// dt; long frame hitches are clamped so the body never "explodes".
  NeuraPose tick(double dt) {
    if (!dt.isFinite || dt <= 0) return _pose;
    if (isStill) return _pose = NeuraPose.neutral;
    dt = math.min(dt, 0.1);
    _clock += dt;

    _maybeIdleAttention();
    _setTargets(dt);

    // Sub-step for stability at the stiffest spring (5 Hz).
    final steps = (dt / (1 / 240)).ceil().clamp(1, 24);
    final h = dt / steps;
    for (var i = 0; i < steps; i++) {
      for (final s in _all) {
        s.step(h);
      }
    }

    for (final g in _gestures) {
      g.t += dt;
    }
    _gestures.removeWhere((g) => g.done);

    // Continuous oscillators layered on top of spring output.
    _breathPhase += dt * 2 * math.pi * _breathRate.value.clamp(0.05, 1.0);
    if (_breathPhase > 2 * math.pi * 1000) _breathPhase -= 2 * math.pi * 1000;
    final amp = _amp.value.clamp(0.0, 1.2);
    final breath = math.sin(_breathPhase);
    final bAmp = _breathAmp.value.clamp(0.0, 3.0) * amp;
    final sAmp = _swayAmp.value.clamp(0.0, 3.0) * amp;
    // Incommensurate frequencies → organic, never-repeating sway.
    final sway = math.sin(_clock * 0.37 + 1.0) * 0.6 +
        math.sin(_clock * 0.61 + 2.3) * 0.4;
    final bob = math.sin(_clock * 0.53) * 0.5 + math.sin(_clock * 0.89) * 0.5;

    // Speech: mouth opening drives a small rhythmic lift so her body is in
    // sync with what she's saying (visemes already drive mouthOpen).
    final speech = _phase == NeuraBodyPhase.speaking ? _mouthOpen : 0.0;

    _pose = NeuraPose(
      dx: _dx.value,
      dy: _dy.value + bob * 0.0045 * sAmp - speech * 0.004 * amp,
      lean: _lean.value + sway * 0.012 * sAmp,
      tilt: _tilt.value + sway * 0.006 * sAmp,
      scale: (_scale.value + breath * 0.008 * bAmp).clamp(0.85, 1.2),
      squash: (_squash.value + breath * 0.006 * bAmp + speech * 0.008 * amp)
          .clamp(-0.12, 0.12),
      glow: (_glow.value + speech * 0.12).clamp(0.0, 1.0),
      warmth: _warmth.value.clamp(-1.0, 1.0),
    );
    if (!_pose.isFinite) {
      // Defensive: never hand a NaN to a Transform.
      for (final s in _all) {
        s.velocity = 0;
      }
      _pose = NeuraPose.neutral;
    }
    return _pose;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  double get _levelAmp => switch (_level) {
        NeuraBodyMotionLevel.still => 0,
        NeuraBodyMotionLevel.subtle => 0.6,
        NeuraBodyMotionLevel.expressive => 1.0,
      };

  void _setTargets(double dt) {
    final amp = _levelAmp;
    final low = (-_mood).clamp(0.0, 1.0); // sadness
    final high = _mood.clamp(0.0, 1.0); // happiness
    final e = _energy;

    // Base posture per phase.
    var dy = 0.0, lean = 0.0, tilt = 0.0, scale = 1.0, glow = 0.15;
    var breathRate = 0.22, breathAmp = 1.0, swayAmp = 1.0;
    switch (_phase) {
      case NeuraBodyPhase.idle:
        break;
      case NeuraBodyPhase.listening:
        scale = 1.02;
        dy = -0.006;
        tilt = 0.035;
        glow = 0.35;
        breathRate = 0.27;
        swayAmp = 0.45; // stillness = attention
      case NeuraBodyPhase.thinking:
        tilt = -0.05 + math.sin(_clock * 0.9) * 0.025; // pondering
        lean = -0.01;
        scale = 0.995;
        glow = 0.3 + 0.12 * (0.5 + 0.5 * math.sin(_clock * 2.4));
        breathRate = 0.17;
        swayAmp = 0.6;
      case NeuraBodyPhase.speaking:
        scale = 1.01;
        dy = -0.004;
        glow = 0.45;
        breathRate = 0.3;
        breathAmp = 1.25;
        swayAmp = 1.2;
      case NeuraBodyPhase.error:
        dy = 0.012;
        scale = 0.98;
        tilt = 0.02;
        glow = 0.1;
        breathRate = 0.2;
        swayAmp = 0.5;
    }

    // Mood & energy shape posture: sad slumps, happy lifts; energy scales life.
    dy += low * 0.014 - high * 0.006;
    lean += -low * 0.01;
    scale += high * 0.012 - low * 0.012;
    breathAmp *= 0.7 + e * 0.6;
    swayAmp *= 0.6 + e * 0.8;
    breathRate += (e - 0.5) * 0.08;

    // Room stance (matches Unity PresentationPose yaw bias).
    lean += switch (_stance) {
      NeuraBodyStance.reflective || NeuraBodyStance.dreaming => -0.018,
      NeuraBodyStance.playful || NeuraBodyStance.guardian => 0.018,
      _ => 0.0,
    };

    // Gestures (additive, enveloped).
    final o = _Offsets();
    for (final g in _gestures) {
      _applyGesture(g, o, e);
    }

    final dxW = _weightTarget * 0.02;
    final leanW = _weightTarget * 0.015;

    _dx.target = (dxW + o.dx) * amp;
    _dy.target = (dy + o.dy) * amp;
    _lean.target = (lean + leanW + o.lean) * amp;
    _tilt.target = (tilt + o.tilt) * amp;
    _scale.target = 1 + (scale - 1 + o.scale) * amp;
    _squash.target = o.squash * amp;
    _glow.target = (glow + o.glow).clamp(0.0, 1.0);
    _warmth.target = _mood;
    _breathRate.target = breathRate;
    _breathAmp.target = breathAmp + o.breath;
    _swayAmp.target = swayAmp;
    _amp.target = amp;
  }

  static double _bell(double u, double c, double w) {
    final x = (u - c) / w;
    return math.exp(-x * x);
  }

  /// Smooth 0→1→0 envelope with soft attack/release.
  static double _env(double u) => math.sin(math.pi * u.clamp(0.0, 1.0));

  void _applyGesture(_ActiveGesture g, _Offsets o, double energy) {
    final u = g.u;
    final k = g.intensity * (0.75 + energy * 0.5);
    switch (g.gesture) {
      case NeuraGesture.nod:
        o.dy += 0.012 * k * _bell(u, 0.35, 0.18);
        o.squash -= 0.03 * k * _bell(u, 0.35, 0.18);
        o.scale -= 0.006 * k * _bell(u, 0.35, 0.2);
      case NeuraGesture.doubleNod:
        final p = _bell(u, 0.25, 0.1) + _bell(u, 0.62, 0.1);
        o.dy += 0.011 * k * p;
        o.squash -= 0.028 * k * p;
      case NeuraGesture.tiltLeft:
        o.tilt -= 0.09 * k * _env(u);
        o.dx -= 0.006 * k * _env(u);
      case NeuraGesture.tiltRight:
        o.tilt += 0.09 * k * _env(u);
        o.dx += 0.006 * k * _env(u);
      case NeuraGesture.bounce:
        // Anticipation squash → hop → landing squash.
        o.squash -= 0.05 * k * _bell(u, 0.12, 0.08);
        o.dy -= 0.045 * k * _bell(u, 0.42, 0.16);
        o.squash += 0.04 * k * _bell(u, 0.42, 0.14);
        o.squash -= 0.035 * k * _bell(u, 0.78, 0.08);
      case NeuraGesture.leanIn:
        o.lean += 0.035 * k * _env(u);
        o.scale += 0.025 * k * _env(u);
        o.dy -= 0.006 * k * _env(u);
        o.glow += 0.15 * k * _env(u);
      case NeuraGesture.leanBack:
        o.lean -= 0.045 * k * _env(u);
        o.scale -= 0.015 * k * _env(u);
        o.squash += 0.02 * k * _bell(u, 0.2, 0.12);
      case NeuraGesture.shake:
        final w = math.sin(u * math.pi * 6) * _env(u);
        o.tilt += 0.05 * k * w;
        o.dx += 0.01 * k * w;
      case NeuraGesture.wave:
        o.dy -= 0.025 * k * _bell(u, 0.3, 0.14);
        o.tilt += 0.06 * k * math.sin(u * math.pi * 3) * _env(u);
        o.glow += 0.25 * k * _env(u);
      case NeuraGesture.settle:
        o.breath += 1.6 * k * _env(u);
        o.dy += 0.008 * k * _bell(u, 0.75, 0.2);
        o.glow += 0.1 * k * _bell(u, 0.4, 0.25);
      case NeuraGesture.celebrate:
        final hop = _bell(u, 0.25, 0.1) + _bell(u, 0.6, 0.1);
        o.dy -= 0.05 * k * hop;
        o.squash += 0.04 * k * hop;
        o.squash -= 0.04 * k * (_bell(u, 0.08, 0.05) + _bell(u, 0.43, 0.05));
        o.tilt += 0.04 * k * math.sin(u * math.pi * 4) * _env(u);
        o.glow += 0.4 * k * _env(u);
      case NeuraGesture.shrug:
        o.squash += 0.045 * k * _bell(u, 0.35, 0.15);
        o.dy -= 0.008 * k * _bell(u, 0.35, 0.15);
        o.tilt += 0.03 * k * _bell(u, 0.4, 0.2);
      case NeuraGesture.glanceLeft:
        o.tilt -= 0.04 * k * _env(u);
      case NeuraGesture.glanceRight:
        o.tilt += 0.04 * k * _env(u);
      case NeuraGesture.lookUp:
        o.dy -= 0.008 * k * _env(u);
        o.squash += 0.015 * k * _env(u);
      case NeuraGesture.lookDown:
        o.dy += 0.01 * k * _env(u);
        o.squash -= 0.015 * k * _env(u);
      case NeuraGesture.stretch:
        o.squash += 0.06 * k * _bell(u, 0.45, 0.22);
        o.dy -= 0.01 * k * _bell(u, 0.45, 0.22);
        o.breath += 1.0 * k * _env(u);
      case NeuraGesture.shiftWeight:
        break; // handled via persistent _weightTarget
    }
  }

  static double _durationOf(NeuraGesture g) => switch (g) {
        NeuraGesture.nod => 0.6,
        NeuraGesture.doubleNod => 0.9,
        NeuraGesture.tiltLeft || NeuraGesture.tiltRight => 1.6,
        NeuraGesture.bounce => 0.75,
        NeuraGesture.leanIn => 2.2,
        NeuraGesture.leanBack => 1.4,
        NeuraGesture.shake => 0.9,
        NeuraGesture.wave => 1.4,
        NeuraGesture.settle => 3.2,
        NeuraGesture.celebrate => 1.3,
        NeuraGesture.shrug => 0.9,
        NeuraGesture.glanceLeft || NeuraGesture.glanceRight => 1.8,
        NeuraGesture.lookUp || NeuraGesture.lookDown => 2.2,
        NeuraGesture.stretch => 2.6,
        NeuraGesture.shiftWeight => 0.1,
      };

  bool _start(NeuraGesture g, double intensity) {
    if (g == NeuraGesture.shiftWeight) {
      _weightTarget = _weightTarget > 0
          ? -(0.4 + _rng.nextDouble() * 0.6)
          : (0.4 + _rng.nextDouble() * 0.6);
      _lastGestureAt = _clock;
      return true;
    }
    // Same gesture restarts rather than stacking.
    _gestures.removeWhere((a) => a.gesture == g);
    if (_gestures.length >= 3) _gestures.removeAt(0);
    _gestures.add(_ActiveGesture(g, intensity, _durationOf(g)));
    _lastGestureAt = _clock;
    return true;
  }

  void _scheduleIdle({double min = 4}) {
    // More energy → she fidgets more often.
    final spread = 8.0 - _energy * 4.0;
    _nextIdleAt = _clock + min + _rng.nextDouble() * spread;
  }

  /// Neura's own attention: when nothing is happening she isn't a statue.
  void _maybeIdleAttention() {
    if (isStill) return;
    if (_phase != NeuraBodyPhase.idle) return;
    if (_clock < _nextIdleAt) return;
    if (_clock - _lastGestureAt < 2.0) {
      _scheduleIdle(min: 2);
      return;
    }
    final choices = <NeuraGesture, double>{
      NeuraGesture.glanceLeft: 2,
      NeuraGesture.glanceRight: 2,
      NeuraGesture.shiftWeight: 2.5,
      NeuraGesture.settle: 1 + (1 - _energy),
      NeuraGesture.lookUp: _mood > 0.25 ? 1.5 : 0.3,
      NeuraGesture.lookDown: _mood < -0.25 ? 1.5 : 0.2,
      NeuraGesture.bounce: (_mood > 0.4 && _energy > 0.6) ? 1.2 : 0,
      NeuraGesture.stretch: _energy < 0.35 ? 0.8 : 0.15,
      NeuraGesture.tiltRight: 0.5,
    };
    final total = choices.values.fold<double>(0, (a, b) => a + b);
    var pick = _rng.nextDouble() * total;
    for (final entry in choices.entries) {
      pick -= entry.value;
      if (pick <= 0) {
        _start(entry.key, 0.35 + _rng.nextDouble() * 0.3);
        break;
      }
    }
    _scheduleIdle();
  }
}
