import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/cognitive/neura_bandwidth_engine.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';

void main() {
  const engine = NeuraBandwidthEngine();

  test('high strain selects recovery mode', () {
    final state = engine.estimate(
      const NeuraCognitiveSignals(
        energy: 0.20,
        focus: 0.18,
        cognitiveLoad: 0.92,
        urgency: 0.88,
        taskSwitchRate: 0.84,
        completionRate: 0.15,
        notificationPressure: 0.90,
      ),
      calculatedAt: DateTime.utc(2026, 8, 22),
    );

    expect(state.mode, NeuraBandwidthMode.recovery);
    expect(state.availableBandwidth, lessThan(0.27));
    expect(state.reasons, isNotEmpty);
  });

  test('high resources and low strain select deep focus', () {
    final state = engine.estimate(
      const NeuraCognitiveSignals(
        energy: 0.95,
        focus: 0.94,
        cognitiveLoad: 0.12,
        urgency: 0.25,
        taskSwitchRate: 0.10,
        completionRate: 0.92,
        notificationPressure: 0.10,
      ),
      calculatedAt: DateTime.utc(2026, 8, 22),
    );

    expect(state.mode, NeuraBandwidthMode.deepFocus);
    expect(state.availableBandwidth, greaterThan(0.72));
  });

  test('Safe Mode always selects recovery', () {
    final state = engine.estimate(
      const NeuraCognitiveSignals(
        energy: 1,
        focus: 1,
        cognitiveLoad: 0,
        urgency: 0,
        taskSwitchRate: 0,
        completionRate: 1,
        notificationPressure: 0,
      ),
      safeMode: true,
      calculatedAt: DateTime.utc(2026, 8, 22),
    );

    expect(state.mode, NeuraBandwidthMode.recovery);
    expect(state.reasons.first, contains('Safe Mode'));
  });

  test('more evidence increases confidence', () {
    const sparse = NeuraCognitiveSignals(
      energy: 0.5,
      focus: 0.5,
      cognitiveLoad: 0.5,
      urgency: 0.5,
      taskSwitchRate: 0.5,
      completionRate: 0.5,
      notificationPressure: 0.5,
      evidenceCount: 1,
      includesSelfReport: false,
    );
    final dense = sparse.copyWith(
      evidenceCount: 7,
      includesSelfReport: true,
    );

    expect(
      engine.estimate(dense).confidence,
      greaterThan(engine.estimate(sparse).confidence),
    );
  });
}
