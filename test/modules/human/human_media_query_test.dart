import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_companion/modules/human/human_media_query.dart';
import 'package:neuro_companion/modules/human/human_prefs.dart';

void main() {
  test('combines Neura and operating-system text scaling', () {
    final source = const MediaQueryData(textScaler: TextScaler.linear(1.25));

    final result = applyHumanAccessibilityPreferences(
      source,
      HumanPrefs.defaults.copyWith(textScale: 1.2),
    );

    expect(result.textScaler.scale(16), closeTo(24, 0.001));
  });

  test('keeps an operating-system reduced-motion request enabled', () {
    final source = const MediaQueryData(
      disableAnimations: true,
      accessibleNavigation: false,
    );

    final result = applyHumanAccessibilityPreferences(
      source,
      HumanPrefs.defaults,
    );

    expect(result.disableAnimations, isTrue);
    expect(result.accessibleNavigation, isTrue);
  });

  test(
    'applies Neura reduced motion when the operating system is animated',
    () {
      final result = applyHumanAccessibilityPreferences(
        const MediaQueryData(),
        HumanPrefs.defaults.copyWith(reducedMotion: true),
      );

      expect(result.disableAnimations, isTrue);
      expect(result.accessibleNavigation, isTrue);
    },
  );

  test('preserves nonlinear operating-system text scaling', () {
    final source = const MediaQueryData(textScaler: _NonlinearTextScaler());

    final result = applyHumanAccessibilityPreferences(
      source,
      HumanPrefs.defaults.copyWith(textScale: 1.5),
    );

    expect(result.textScaler.scale(12), closeTo(21.6, 0.001));
    expect(result.textScaler.scale(24), closeTo(57.6, 0.001));
  });

  test('keeps screen-reader navigation even without reduced motion', () {
    final result = applyHumanAccessibilityPreferences(
      const MediaQueryData(accessibleNavigation: true),
      HumanPrefs.defaults,
    );

    expect(result.accessibleNavigation, isTrue);
    expect(result.disableAnimations, isFalse);
  });

  test('clamps very large combined text scaling', () {
    final result = applyHumanAccessibilityPreferences(
      const MediaQueryData(textScaler: TextScaler.linear(3)),
      HumanPrefs.defaults.copyWith(textScale: 2),
    );

    expect(result.textScaler.scale(16), 64);
  });
}

class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  double scale(double fontSize) {
    return fontSize * (fontSize < 20 ? 1.2 : 1.6);
  }
}
