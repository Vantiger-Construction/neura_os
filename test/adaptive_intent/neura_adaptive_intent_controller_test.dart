import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_controller.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';

void main() {
  test('controller recomputes mode and invalidates an old plan', () {
    final controller = NeuraAdaptiveIntentController();
    addTearDown(controller.dispose);

    controller.compileOutcome(
      'Organize my priorities',
      now: DateTime.utc(2026, 8, 22, 15),
    );
    expect(controller.plan, isNotNull);

    controller.updateSignals(
      energy: 0.10,
      focus: 0.10,
      cognitiveLoad: 0.95,
      taskSwitchRate: 0.95,
      notificationPressure: 0.95,
      completionRate: 0.10,
    );

    expect(controller.state.mode, NeuraBandwidthMode.recovery);
    expect(controller.plan, isNull);
  });

  test('Safe Mode invalidates plan and forces conservative policy', () {
    final controller = NeuraAdaptiveIntentController();
    addTearDown(controller.dispose);

    controller.compileOutcome(
      'Plan my week',
      now: DateTime.utc(2026, 8, 22, 15),
    );
    controller.setSafeMode(true);

    expect(controller.state.mode, NeuraBandwidthMode.recovery);
    expect(controller.interfacePolicy.externalEffectsAllowed, isFalse);
    expect(controller.plan, isNull);
  });
}
