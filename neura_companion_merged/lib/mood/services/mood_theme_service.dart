import 'package:flutter/material.dart';

class NeuraMoodTheme {
  final String mood;
  final Gradient background;
  final Color accent;
  final String difficulty; // gentle / normal / challenge

  const NeuraMoodTheme({
    required this.mood,
    required this.background,
    required this.accent,
    required this.difficulty,
  });
}

class MoodThemeService {
  MoodThemeService._internal();
  static final MoodThemeService instance = MoodThemeService._internal();

  NeuraMoodTheme themeFor(String moodRaw) {
    final mood = moodRaw.toLowerCase();
    switch (mood) {
      case 'sad':
        return NeuraMoodTheme(
          mood: mood,
          background: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF283593)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          accent: Colors.lightBlueAccent,
          difficulty: 'gentle',
        );
      case 'anxious':
      case 'scared':
        return NeuraMoodTheme(
          mood: mood,
          background: const LinearGradient(
            colors: [Color(0xFF311B92), Color(0xFF4527A0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          accent: Colors.amberAccent,
          difficulty: 'gentle',
        );
      case 'angry':
        return NeuraMoodTheme(
          mood: mood,
          background: const LinearGradient(
            colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          accent: Colors.orangeAccent,
          difficulty: 'gentle',
        );
      case 'tired':
        return NeuraMoodTheme(
          mood: mood,
          background: const LinearGradient(
            colors: [Color(0xFF263238), Color(0xFF37474F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          accent: Colors.cyanAccent,
          difficulty: 'gentle',
        );
      case 'calm':
        return NeuraMoodTheme(
          mood: mood,
          background: const LinearGradient(
            colors: [Color(0xFF004D40), Color(0xFF00796B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          accent: Colors.tealAccent,
          difficulty: 'normal',
        );
      case 'happy':
      case 'excited':
        return NeuraMoodTheme(
          mood: mood,
          background: const LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          accent: Colors.limeAccent,
          difficulty: 'challenge',
        );
      default:
        return const NeuraMoodTheme(
          mood: 'neutral',
          background: LinearGradient(
            colors: [Color(0xFF263238), Color(0xFF1E88E5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          accent: Colors.cyanAccent,
          difficulty: 'normal',
        );
    }
  }
}
