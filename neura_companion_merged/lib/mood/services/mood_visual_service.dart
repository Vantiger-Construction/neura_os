import 'package:flutter/material.dart';

import '../models/mood_state.dart';
import '../models/mood_visual_style.dart';

class MoodVisualService {
  MoodVisualService._internal();
  static final MoodVisualService instance = MoodVisualService._internal();

  MoodVisualStyle styleFor(MoodState state) {
    final score = state.score.clamp(0.0, 10.0);
    if (score <= 2.5) {
      // Very heavy mood -> calmer, darker, softer
      return const MoodVisualStyle(
        backgroundTop: Color(0xFF141726),
        backgroundBottom: Color(0xFF1F2538),
        accent: Color(0xFFFFB4A2),
        difficultyMultiplier: 0.5,
      );
    } else if (score <= 4.0) {
      // Low mood -> soft, muted
      return const MoodVisualStyle(
        backgroundTop: Color(0xFF1E2233),
        backgroundBottom: Color(0xFF252B3E),
        accent: Color(0xFFFFD6A5),
        difficultyMultiplier: 0.7,
      );
    } else if (score <= 6.0) {
      // Neutral
      return const MoodVisualStyle(
        backgroundTop: Color(0xFF101827),
        backgroundBottom: Color(0xFF111827),
        accent: Color(0xFF7DD3FC),
        difficultyMultiplier: 1.0,
      );
    } else if (score <= 8.0) {
      // Lifted
      return const MoodVisualStyle(
        backgroundTop: Color(0xFF0F172A),
        backgroundBottom: Color(0xFF1D283A),
        accent: Color(0xFF6EE7B7),
        difficultyMultiplier: 1.1,
      );
    } else {
      // Very high / energized
      return const MoodVisualStyle(
        backgroundTop: Color(0xFF020617),
        backgroundBottom: Color(0xFF0F172A),
        accent: Color(0xFFFBBF24),
        difficultyMultiplier: 1.25,
      );
    }
  }

  /// Maps mood + base difficulty string -> final difficulty string.
  /// baseDifficulty: 'gentle' | 'normal' | 'challenge'
  String adaptDifficulty(String baseDifficulty, MoodState state) {
    final score = state.score.clamp(0.0, 10.0);
    final base = baseDifficulty.toLowerCase();
    if (score <= 3.5) {
      // When you're low, everything should default to gentle.
      return 'gentle';
    }
    if (score >= 8.0 && base != 'gentle') {
      // When you're very energized and not explicitly gentle, we can lean
      // into a small challenge.
      return 'challenge';
    }
    // Otherwise keep what the module wanted.
    return base;
  }
}
