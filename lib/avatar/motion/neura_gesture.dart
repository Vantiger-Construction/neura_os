// lib/avatar/motion/neura_gesture.dart
//
// Neura's body-language vocabulary.
//
// This is a CLOSED allow-list. Anything that reaches the motion engine from
// outside the app (the brain, a future Unity host, the mascot isolate) is
// matched against [NeuraGesture.fromWire] and silently dropped if unknown.
// Gestures are presentation-only: they carry no text, no content and grant no
// authority. Safe Mode and the "Still" preference suppress all of them.

import '../../core/neura_events.dart';

enum NeuraGesture {
  // ── Brain-callable (allowed on the wire) ────────────────────────────────
  /// Single agreeable nod.
  nod,

  /// Two quick nods — enthusiastic agreement.
  doubleNod,

  /// Curious head tilt to her left.
  tiltLeft,

  /// Curious head tilt to her right.
  tiltRight,

  /// Small happy hop.
  bounce,

  /// Leans toward the user — attentive / empathetic.
  leanIn,

  /// Leans back — surprise or "let me consider that".
  leanBack,

  /// Gentle side-to-side "no" / something went wrong.
  shake,

  /// Friendly greeting: hop + tilt (a single 2D figure has no arm rig).
  wave,

  /// Slow deep breath — calming, grounding.
  settle,

  /// Big double hop.
  celebrate,

  /// Quick lift-and-drop of the whole body.
  shrug,

  // ── Internal-only (Neura's own idle attention; never accepted on wire) ──
  glanceLeft,
  glanceRight,
  shiftWeight,
  lookUp,
  lookDown,
  stretch;

  /// Gestures an external source (brain envelope, mascot bridge) may request.
  static const Set<NeuraGesture> wireAllowed = {
    nod,
    doubleNod,
    tiltLeft,
    tiltRight,
    bounce,
    leanIn,
    leanBack,
    shake,
    wave,
    settle,
    celebrate,
    shrug,
  };

  /// Strict parse of a wire name. Returns null for anything not allow-listed.
  /// Accepts `snake_case` and `camelCase` (`double_nod` == `doubleNod`).
  static NeuraGesture? fromWire(Object? raw) {
    if (raw is! String || raw.isEmpty || raw.length > 24) return null;
    final key = raw.replaceAll('_', '').replaceAll('-', '').toLowerCase();
    for (final g in wireAllowed) {
      if (g.name.toLowerCase() == key) return g;
    }
    return null;
  }

  /// snake_case wire name, used by the mascot bridge.
  String get wireName => name.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (m) => '_${m[0]!.toLowerCase()}',
      );
}

/// Ask Neura's body to perform a gesture. [intensity] is clamped to 0..1.
class NeuraGestureEvent extends NeuraEvent {
  final NeuraGesture gesture;
  final double intensity;
  const NeuraGestureEvent(this.gesture, {this.intensity = 0.7});

  @override
  String toString() => 'NeuraGestureEvent(${gesture.name}, $intensity)';
}
