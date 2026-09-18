import 'package:flutter/material.dart';

import 'human_prefs.dart';

/// Applies Neura's explicit accessibility preferences without discarding the
/// operating system's own text scale or reduced-motion request.
MediaQueryData applyHumanAccessibilityPreferences(
  MediaQueryData source,
  HumanPrefs prefs,
) {
  const referenceFontSize = 16.0;
  final systemScale =
      source.textScaler.scale(referenceFontSize) / referenceFontSize;
  final combinedScale =
      (systemScale * prefs.textScale).clamp(0.85, 4.0).toDouble();
  final reduceMotion = source.disableAnimations || prefs.reducedMotion;

  return source.copyWith(
    textScaler: TextScaler.linear(combinedScale),
    disableAnimations: reduceMotion,
    accessibleNavigation: source.accessibleNavigation || reduceMotion,
  );
}
