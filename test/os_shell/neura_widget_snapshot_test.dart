import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/os_shell/widgets_bridge/neura_widget_snapshot.dart';

void main() {
  group('buildNeuraWidgetSnapshot', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test('Safe Mode blanks every field regardless of other inputs', () {
      final snapshot = buildNeuraWidgetSnapshot(
        safeMode: true,
        now: now,
        lastMoodValue: 7,
        lastMoodAt: now.subtract(const Duration(hours: 1)),
        approvedNudgeTitle: 'A gentle reset is available',
      );

      expect(snapshot.safeMode, isTrue);
      expect(snapshot.moodValue, isNull);
      expect(snapshot.moodAgeLabel, isNull);
      expect(snapshot.nudgeTitle, isNull);
    });

    test('mirrors mood value and age when present and not in Safe Mode', () {
      final snapshot = buildNeuraWidgetSnapshot(
        safeMode: false,
        now: now,
        lastMoodValue: 6,
        lastMoodAt: now.subtract(const Duration(hours: 2)),
      );

      expect(snapshot.safeMode, isFalse);
      expect(snapshot.moodValue, 6);
      expect(snapshot.moodAgeLabel, '2h ago');
    });

    test('omits mood fields entirely when there is no mood history', () {
      final snapshot = buildNeuraWidgetSnapshot(safeMode: false, now: now);

      expect(snapshot.moodValue, isNull);
      expect(snapshot.moodAgeLabel, isNull);
    });

    test('only mirrors a nudge title that was passed in, never invents one',
        () {
      final withNudge = buildNeuraWidgetSnapshot(
        safeMode: false,
        now: now,
        approvedNudgeTitle: 'Try a 15-minute focus sprint',
      );
      final withoutNudge = buildNeuraWidgetSnapshot(safeMode: false, now: now);

      expect(withNudge.nudgeTitle, 'Try a 15-minute focus sprint');
      expect(withoutNudge.nudgeTitle, isNull);
    });
  });

  group('relativeAgeLabel', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test('renders sub-minute as "just now"', () {
      expect(
        relativeAgeLabel(
            now: now, then: now.subtract(const Duration(seconds: 30))),
        'just now',
      );
    });

    test('renders minutes, hours, and days at their own scale', () {
      expect(
        relativeAgeLabel(
            now: now, then: now.subtract(const Duration(minutes: 5))),
        '5m ago',
      );
      expect(
        relativeAgeLabel(
            now: now, then: now.subtract(const Duration(hours: 3))),
        '3h ago',
      );
      expect(
        relativeAgeLabel(now: now, then: now.subtract(const Duration(days: 2))),
        '2d ago',
      );
    });

    test('a future timestamp (clock skew) never shows a negative duration', () {
      expect(
        relativeAgeLabel(now: now, then: now.add(const Duration(minutes: 5))),
        'just now',
      );
    });
  });

  group('NeuraWidgetSnapshot.toWidgetData', () {
    test('blank snapshot serialises to safe-mode-on with empty fields', () {
      const snapshot = NeuraWidgetSnapshot.blank();
      expect(snapshot.toWidgetData(), {
        'neura_widget_safe_mode': '1',
        'neura_widget_mood_value': '',
        'neura_widget_mood_age': '',
        'neura_widget_nudge_title': '',
      });
    });

    test('a populated snapshot serialises every field to a string', () {
      const snapshot = NeuraWidgetSnapshot(
        safeMode: false,
        moodValue: 8,
        moodAgeLabel: '1h ago',
        nudgeTitle: 'A gentle reset is available',
      );
      expect(snapshot.toWidgetData(), {
        'neura_widget_safe_mode': '0',
        'neura_widget_mood_value': '8',
        'neura_widget_mood_age': '1h ago',
        'neura_widget_nudge_title': 'A gentle reset is available',
      });
    });
  });
}
