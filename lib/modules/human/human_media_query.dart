import 'package:flutter/material.dart';

import 'human_prefs.dart';

/// Applies Neura's explicit accessibility preferences without discarding the
/// operating system's own text scale or reduced-motion request.
MediaQueryData applyHumanAccessibilityPreferences(
  MediaQueryData source,
  HumanPrefs prefs,
) {
  final reduceMotion = source.disableAnimations || prefs.reducedMotion;

  return source.copyWith(
    textScaler: _HumanPreferenceTextScaler(
      source.textScaler,
      userScale: prefs.textScale,
    ),
    disableAnimations: reduceMotion,
    accessibleNavigation: source.accessibleNavigation || reduceMotion,
  );
}

class _HumanPreferenceTextScaler extends TextScaler {
  const _HumanPreferenceTextScaler(
    this.systemScaler, {
    required this.userScale,
  });

  final TextScaler systemScaler;
  final double userScale;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  double scale(double fontSize) {
    final min = fontSize * 0.85;
    final max = fontSize * 4.0;
    return (systemScaler.scale(fontSize) * userScale)
        .clamp(min, max)
        .toDouble();
  }
}
