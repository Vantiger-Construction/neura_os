import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/intelligence_preferences.dart';

void main() {
  group('NeuraIntelligencePreferences JSON', () {
    test('uses privacy-conscious defaults when fields are absent', () {
      final preferences = NeuraIntelligencePreferences.fromJson(
        const <String, Object?>{},
      );

      expect(preferences.enabled, isTrue);
      expect(
        preferences.proactivityLevel,
        NeuraProactivityLevel.balanced,
      );
      expect(preferences.allowsProactiveSuggestions, isTrue);
      expect(preferences.effectiveMaxDailySuggestions, 3);
      expect(preferences.allowSensitiveSignals, isFalse);
      expect(preferences.showDecisionReasons, isTrue);
      expect(preferences.maxDailySuggestions, 3);
      expect(preferences.quietHoursEnabled, isFalse);
      expect(preferences.quietHoursStart, 22);
      expect(preferences.quietHoursEnd, 7);
      expect(preferences.pausedUntil, isNull);
    });

    test('migrates a legacy disabled preference to the explicit off level',
        () {
      final preferences = NeuraIntelligencePreferences.fromJson(
        const <String, Object?>{'enabled': false},
      );

      expect(preferences.proactivityLevel, NeuraProactivityLevel.off);
      expect(preferences.allowsProactiveSuggestions, isFalse);
      expect(preferences.effectiveMaxDailySuggestions, 0);
    });

    test('round-trips subtle proactivity and tightens the daily cap', () {
      const original = NeuraIntelligencePreferences(
        proactivityLevel: NeuraProactivityLevel.subtle,
        maxDailySuggestions: 6,
      );
      final restored = NeuraIntelligencePreferences.fromJson(
        original.toJson(),
      );

      expect(restored.proactivityLevel, NeuraProactivityLevel.subtle);
      expect(restored.effectiveMaxDailySuggestions, 1);
      expect(
        restored.proactivityLevel.appOpenCooldown,
        const Duration(hours: 24),
      );
    });

    test('off remains fail-closed across legacy and level updates', () {
      final legacyOff = const NeuraIntelligencePreferences().copyWith(
        enabled: false,
      );
      final levelOff = const NeuraIntelligencePreferences().copyWith(
        proactivityLevel: NeuraProactivityLevel.off,
      );

      expect(legacyOff.proactivityLevel, NeuraProactivityLevel.off);
      expect(legacyOff.effectiveMaxDailySuggestions, 0);
      expect(levelOff.enabled, isFalse);
      expect(levelOff.toJson()['enabled'], isFalse);
    });

    test('clamps persisted and copied numeric policy values', () {
      final persisted = NeuraIntelligencePreferences.fromJson(
        const <String, Object?>{
          'max_daily_suggestions': -20,
          'quiet_hours_start': -5,
          'quiet_hours_end': 99,
        },
      );
      final copied = const NeuraIntelligencePreferences().copyWith(
        maxDailySuggestions: 50,
        quietHoursStart: 40,
        quietHoursEnd: -10,
      );

      expect(persisted.maxDailySuggestions, 1);
      expect(persisted.quietHoursStart, 0);
      expect(persisted.quietHoursEnd, 23);
      expect(copied.maxDailySuggestions, 6);
      expect(copied.quietHoursStart, 23);
      expect(copied.quietHoursEnd, 0);
    });

    test('round-trips a pause by instant and can explicitly clear it', () {
      final pausedUntil = DateTime.parse('2026-08-15T02:30:00-05:00');
      final original = NeuraIntelligencePreferences(pausedUntil: pausedUntil);
      final restored = NeuraIntelligencePreferences.fromJson(
        original.toJson(),
      );

      expect(restored.pausedUntil, isNotNull);
      expect(
        restored.pausedUntil!.isAtSameMomentAs(pausedUntil),
        isTrue,
      );
      expect(
        restored.isQuietAt(pausedUntil.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(restored.isQuietAt(pausedUntil), isFalse);
      expect(restored.copyWith(clearPause: true).pausedUntil, isNull);
    });
  });

  group('NeuraIntelligencePreferences quiet hours', () {
    test('handles an overnight window with an exclusive end hour', () {
      const preferences = NeuraIntelligencePreferences(
        quietHoursEnabled: true,
        quietHoursStart: 22,
        quietHoursEnd: 7,
      );

      expect(preferences.isQuietAt(DateTime(2026, 8, 14, 21, 59)), isFalse);
      expect(preferences.isQuietAt(DateTime(2026, 8, 14, 22)), isTrue);
      expect(preferences.isQuietAt(DateTime(2026, 8, 15, 6, 59)), isTrue);
      expect(preferences.isQuietAt(DateTime(2026, 8, 15, 7)), isFalse);
    });

    test('treats matching start and end hours as an all-day window', () {
      const preferences = NeuraIntelligencePreferences(
        quietHoursEnabled: true,
        quietHoursStart: 9,
        quietHoursEnd: 9,
      );

      expect(preferences.isQuietAt(DateTime(2026, 8, 14, 0)), isTrue);
      expect(preferences.isQuietAt(DateTime(2026, 8, 14, 12)), isTrue);
      expect(preferences.isQuietAt(DateTime(2026, 8, 14, 23, 59)), isTrue);
    });
  });
}
