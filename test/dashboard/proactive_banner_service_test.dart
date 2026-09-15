import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_companion/dashboard/proactive_banner_service.dart';
import 'package:neuro_companion/relationships/services/distress_detector.dart';

class _FakeDistressDetector extends DistressDetector {
  _FakeDistressDetector(this.result);

  final DistressSignal result;

  @override
  DistressSignal detect({
    required List<int> recentMoods,
    required int appOpensLastHour,
    required bool lotsOfNegativeWords,
  }) =>
      result;
}

void main() {
  group('ProactiveBannerService.computeDistressScore', () {
    test('falls back to raw mood arithmetic when the detector is inactive', () {
      final score = ProactiveBannerService.computeDistressScore(
        moodValue: 0.2,
        recentMoods: const [],
        detector: _FakeDistressDetector(DistressSignal(active: false)),
      );

      expect(score, closeTo((0.5 - 0.2) * 1.4, 0.0001));
    });

    test('a mild mood reading is overridden by a corroborated real signal', () {
      // A single mild mood sample alone would score low, but a synthetic
      // detector result reporting active distress must still dominate.
      final score = ProactiveBannerService.computeDistressScore(
        moodValue: 0.48,
        recentMoods: const [-2, -2, -2],
        detector: _FakeDistressDetector(DistressSignal(active: true)),
      );

      expect(score, greaterThanOrEqualTo(0.75));
      expect(score, lessThanOrEqualTo(1.0));
    });

    test('a null mood value with an inactive detector scores zero', () {
      final score = ProactiveBannerService.computeDistressScore(
        moodValue: null,
        recentMoods: const [],
        detector: _FakeDistressDetector(DistressSignal(active: false)),
      );

      expect(score, 0.0);
    });

    test('the score always stays within the 0..1 guardrail contract', () {
      final score = ProactiveBannerService.computeDistressScore(
        moodValue: -5,
        recentMoods: const [],
        detector: _FakeDistressDetector(DistressSignal(active: false)),
      );

      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(1.0));
    });

    test('uses a lower local-card threshold for several low moods', () {
      final sharedSignal = const DistressDetector().detect(
        recentMoods: const [-2, -2, -2],
        appOpensLastHour: 0,
        lotsOfNegativeWords: false,
      );
      final score = ProactiveBannerService.computeDistressScore(
        moodValue: 0.45,
        recentMoods: const [-2, -2, -2],
      );

      // Chat and other high-impact consumers retain the shared detector's
      // conservative threshold; only this local, reversible card responds.
      expect(sharedSignal.active, isFalse);
      expect(score, greaterThanOrEqualTo(0.75));
    });
  });

  group('ProactiveBannerService.isStreakMilestone', () {
    test('fires only on round-number streak lengths in a synthetic sequence',
        () {
      final sequence = [
        for (var streak = 1; streak <= 32; streak++) streak,
      ];
      final milestonesHit =
          sequence.where(ProactiveBannerService.isStreakMilestone).toList();

      expect(milestonesHit, [7, 14, 30]);
    });

    test('a streak that never lands on a milestone never fires', () {
      final sequence = [3, 5, 8, 9, 10, 11, 12, 13, 29, 31];

      expect(sequence.any(ProactiveBannerService.isStreakMilestone), isFalse);
    });
  });
}
