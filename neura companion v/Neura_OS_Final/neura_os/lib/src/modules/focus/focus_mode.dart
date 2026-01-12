import 'package:flutter/material.dart';

enum FocusMode {
  off,
  deepWork,
  reflection,
  social,
  windDown,
}

extension FocusModeX on FocusMode {
  String get label => switch (this) {
        FocusMode.off => 'Off',
        FocusMode.deepWork => 'Deep Work',
        FocusMode.reflection => 'Reflection',
        FocusMode.social => 'Social',
        FocusMode.windDown => 'Wind Down',
      };

  String get subtitle => switch (this) {
        FocusMode.off => 'No special mode — normal Neura OS.',
        FocusMode.deepWork => 'Less noise, more momentum.',
        FocusMode.reflection => 'Gentle prompts and quiet UI.',
        FocusMode.social => 'Open, expressive, outward-facing.',
        FocusMode.windDown => 'Lower stimulation, bedtime brain.',
      };

  IconData get icon => switch (this) {
        FocusMode.off => Icons.blur_on,
        FocusMode.deepWork => Icons.psychology_alt_outlined,
        FocusMode.reflection => Icons.self_improvement_outlined,
        FocusMode.social => Icons.people_outline,
        FocusMode.windDown => Icons.bedtime_outlined,
      };

  Color? get accent => switch (this) {
        FocusMode.off => null,
        FocusMode.deepWork => const Color(0xFF00E5FF),
        FocusMode.reflection => const Color(0xFFB388FF),
        FocusMode.social => const Color(0xFFFFD54F),
        FocusMode.windDown => const Color(0xFF80CBC4),
      };
}
