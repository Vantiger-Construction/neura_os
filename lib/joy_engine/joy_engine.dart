import 'dart:math';
import 'joy_moments.dart';
import 'joy_types.dart';

/// JoyEngine picks a "Joy Moment" that is mood-aware and safe.
/// No addictive loops. Always short. Always skippable.
class JoyEngine {
  final Random _rng;
  JoyEngine({Random? rng}) : _rng = rng ?? Random();

  JoyMoment pickMoment(
    NeuraMood mood, {
    NeuraIntent? intent,
    JoyPreferenceProfile? prefs,
  }) {
    final pool = JoyMoments.poolFor(mood, intent: intent, prefs: prefs);
    if (pool.isEmpty) return JoyMoments.fallback();
    return pool[_rng.nextInt(pool.length)];
  }
}
