import 'package:flutter/material.dart';

class MoodVisualStyle {
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color accent;
  final double difficultyMultiplier;

  const MoodVisualStyle({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.accent,
    required this.difficultyMultiplier,
  });
}
