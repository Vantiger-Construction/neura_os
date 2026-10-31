// lib/avatar/motion/neura_body_cues.dart
//
// How Neura's *mind* reaches her *body* — three channels, all presentation-only
// and content-free (no text ever leaves this file; only gesture enums and
// mood/energy numbers are emitted onto the NeuraEventBus):
//
//  1. TONE      `set_tone` from the brain → posture via mood/energy.
//  2. RHYTHM    Her own speech, sentence by sentence, synced to TTS progress:
//               openings nod, questions tilt, exclamations bounce. Only
//               punctuation classes are inspected — never words.
//  3. CUES      `avatar_cue` envelope from the brain for deliberate gestures:
//               {"gesture":"nod","intensity":0.6,"mood":0.4,"energy":0.7}
//               Validated against NeuraGesture.wireAllowed and rate-limited.
//
// This keeps the repo invariant intact: the UI never treats model output as a
// command. Unknown/oversized/malformed cues are dropped silently.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/neura_event_bus.dart';
import '../../core/neura_events.dart';
import '../../neura_link/neura_tone.dart';
import 'neura_gesture.dart';

// ───────────────────────────────────────────────────────────────────────────
// 1. Tone → mood/energy
// ───────────────────────────────────────────────────────────────────────────

class NeuraToneMotion {
  const NeuraToneMotion._();

  /// (mood −1..1, energy 0..1) for each brain tone.
  static (double, double) moodFor(NeuraTone tone) => switch (tone) {
        NeuraTone.calm => (0.2, 0.3),
        NeuraTone.warm => (0.6, 0.55),
        NeuraTone.focused => (0.1, 0.6),
        NeuraTone.hopeful => (0.55, 0.7),
        NeuraTone.alert => (-0.2, 0.85),
        NeuraTone.neutral => (0.0, 0.5),
      };

  /// A small acknowledgement gesture when her tone shifts.
  static NeuraGesture? flourishFor(NeuraTone tone) => switch (tone) {
        NeuraTone.warm => NeuraGesture.leanIn,
        NeuraTone.hopeful => NeuraGesture.bounce,
        NeuraTone.calm => NeuraGesture.settle,
        NeuraTone.alert => NeuraGesture.leanBack,
        _ => null,
      };

  static void apply(NeuraTone tone,
      {NeuraEventBus? bus, bool flourish = true}) {
    final b = bus ?? NeuraEventBus.I;
    final (mood, energy) = moodFor(tone);
    b.emit(NeuraMoodEvent(mood: mood, energy: energy));
    final g = flourish ? flourishFor(tone) : null;
    if (g != null) b.emit(NeuraGestureEvent(g, intensity: 0.45));
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 2. Speech rhythm → gestures
// ───────────────────────────────────────────────────────────────────────────

/// Punctuation class of a sentence — the ONLY thing derived from speech text.
enum NeuraSentenceKind { opening, statement, question, exclamation, trailing }

class NeuraSpeechBeats {
  NeuraSpeechBeats({NeuraEventBus? bus, math.Random? random})
      : _bus = bus ?? NeuraEventBus.I,
        _rng = random ?? math.Random();

  static final NeuraSpeechBeats instance = NeuraSpeechBeats();

  final NeuraEventBus _bus;
  final math.Random _rng;

  /// Sentence end offsets + kinds for the current utterance. No text kept.
  List<(int, NeuraSentenceKind)> _beats = const [];
  int _next = 0;
  bool _progressSeen = false;
  final List<Timer> _timers = [];
  bool _tiltLeftNext = false;

  /// Approximate speaking speed for the timer fallback (chars/sec).
  static const double _charsPerSecond = 14;

  /// Split into sentence beats. Pure; exposed for tests.
  ///
  /// Each sentence gets a beat where it starts (the first one is the
  /// "opening"); questions, exclamations and trailing-off sentences also get a
  /// beat just before they end, so she tilts *while* asking.
  @visibleForTesting
  static List<(int, NeuraSentenceKind)> analyze(String text) {
    final beats = <(int, NeuraSentenceKind)>[];
    final re = RegExp(r'[^.!?\u2026]+(?:[.!?\u2026]+["\u201d\u2019)\]]*|$)');
    for (final m in re.allMatches(text)) {
      final s = m.group(0)!;
      if (s.trim().length < 2) continue;
      final lead = m.start + (s.length - s.trimLeft().length);
      beats.add((
        lead,
        beats.isEmpty ? NeuraSentenceKind.opening : NeuraSentenceKind.statement,
      ));
      final tail = s.trimRight();
      final NeuraSentenceKind? kind = tail.contains('?')
          ? NeuraSentenceKind.question
          : tail.contains('!')
              ? NeuraSentenceKind.exclamation
              : (tail.endsWith('\u2026') || tail.endsWith('..'))
                  ? NeuraSentenceKind.trailing
                  : null;
      if (kind == null) continue;
      final at = m.start + tail.length - 8;
      if (at > lead + 4) {
        beats.add((at, kind));
      } else {
        // Short line: its expressive kind beats a plain nod.
        beats[beats.length - 1] = (lead, kind);
      }
    }
    return beats;
  }

  NeuraGesture? gestureFor(NeuraSentenceKind kind) {
    switch (kind) {
      case NeuraSentenceKind.opening:
        return NeuraGesture.nod;
      case NeuraSentenceKind.question:
        _tiltLeftNext = !_tiltLeftNext;
        return _tiltLeftNext ? NeuraGesture.tiltLeft : NeuraGesture.tiltRight;
      case NeuraSentenceKind.exclamation:
        return NeuraGesture.bounce;
      case NeuraSentenceKind.trailing:
        return NeuraGesture.settle;
      case NeuraSentenceKind.statement:
        // Not every sentence — that reads robotic.
        return _rng.nextDouble() < 0.45 ? NeuraGesture.nod : null;
    }
  }

  void _fire(NeuraSentenceKind kind) {
    final g = gestureFor(kind);
    if (g == null) return;
    final intensity = switch (kind) {
      NeuraSentenceKind.exclamation => 0.75,
      NeuraSentenceKind.question => 0.6,
      NeuraSentenceKind.opening => 0.5,
      _ => 0.35,
    };
    _bus.emit(NeuraGestureEvent(g, intensity: intensity));
  }

  /// Call right before the native TTS engine starts [text].
  void begin(String text) {
    end();
    if (text.length > 20000) return;
    _beats = analyze(text);
    _next = 0;
    _progressSeen = false;
    // Fallback schedule for engines that never report progress.
    for (var i = 0; i < _beats.length; i++) {
      final (offset, _) = _beats[i];
      final idx = i;
      _timers.add(Timer(
        Duration(milliseconds: (offset / _charsPerSecond * 1000).round() + 120),
        () {
          if (_progressSeen || idx < _next) return;
          _advanceTo(idx);
        },
      ));
    }
  }

  /// Feed TTS word-progress (character offset into the utterance).
  void progress(int start) {
    _progressSeen = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    var target = _next - 1;
    for (var i = _next; i < _beats.length; i++) {
      if (_beats[i].$1 <= start) target = i;
    }
    if (target >= _next) _advanceTo(target);
  }

  void _advanceTo(int idx) {
    // Fire only the newest beat if several were skipped (fast speech).
    _fire(_beats[idx].$2);
    _next = idx + 1;
  }

  /// Speech finished / cancelled / errored.
  void end() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _beats = const [];
    _next = 0;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 3. Brain cue envelope gate
// ───────────────────────────────────────────────────────────────────────────

class NeuraAvatarCueGate {
  NeuraAvatarCueGate({NeuraEventBus? bus, DateTime Function()? now})
      : _bus = bus ?? NeuraEventBus.I,
        _now = now ?? DateTime.now;

  static final NeuraAvatarCueGate instance = NeuraAvatarCueGate();

  final NeuraEventBus _bus;
  final DateTime Function() _now;
  final List<DateTime> _recent = [];

  static const Duration minSpacing = Duration(milliseconds: 350);
  static const Duration window = Duration(seconds: 5);
  static const int maxPerWindow = 6;
  static const Set<String> _allowedKeys = {
    'gesture',
    'intensity',
    'mood',
    'energy',
  };

  /// Validate and apply an `avatar_cue` envelope's `data`. Returns true if
  /// anything was applied. Never throws.
  bool apply(Map<String, dynamic> data) {
    try {
      if (data.isEmpty || data.length > _allowedKeys.length) return false;
      if (data.keys.any((k) => !_allowedKeys.contains(k))) return false;

      final now = _now();
      _recent.removeWhere((t) => now.difference(t) > window);
      if (_recent.isNotEmpty && now.difference(_recent.last) < minSpacing) {
        return false;
      }
      if (_recent.length >= maxPerWindow) return false;

      var applied = false;
      final mood = _num(data['mood'], -1, 1);
      final energy = _num(data['energy'], 0, 1);
      if (data.containsKey('mood') && mood == null) return false;
      if (data.containsKey('energy') && energy == null) return false;
      final gesture = NeuraGesture.fromWire(data['gesture']);
      final intensity =
          data.containsKey('intensity') ? _num(data['intensity'], 0, 1) : 0.7;
      if (data.containsKey('gesture') && gesture == null) return false;
      if (intensity == null ||
          data.containsKey('intensity') && gesture == null) {
        return false;
      }
      if (mood != null || energy != null) {
        _bus.emit(NeuraMoodEvent(mood: mood ?? 0, energy: energy ?? 0.5));
        applied = true;
      }

      if (gesture != null) {
        _bus.emit(NeuraGestureEvent(gesture, intensity: intensity));
        applied = true;
      }
      if (applied) _recent.add(now);
      return applied;
    } catch (_) {
      return false;
    }
  }

  static double? _num(Object? v, double lo, double hi) {
    if (v is! num) return null;
    final d = v.toDouble();
    if (!d.isFinite) return null;
    return d.clamp(lo, hi);
  }
}
