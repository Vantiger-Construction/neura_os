import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_controller.dart';
import 'package:neuro_companion/cognitive/neura_cognitive_state.dart';

void main() {
  test('live evidence metadata reaches the bandwidth estimator', () {
    final controller = NeuraAdaptiveIntentController(
      signals: const NeuraCognitiveSignals(
        energy: 0.60,
        focus: 0.60,
        cognitiveLoad: 0.40,
        urgency: 0.30,
        taskSwitchRate: 0.30,
        completionRate: 0.60,
        notificationPressure: 0.30,
        evidenceCount: 0,
        includesSelfReport: false,
      ),
    );
    addTearDown(controller.dispose);

    final initialConfidence = controller.state.confidence;

    controller.updateSignals(
      evidenceCount: 6,
      includesSelfReport: true,
    );

    expect(controller.signals.evidenceCount, 6);
    expect(controller.signals.includesSelfReport, isTrue);
    expect(controller.state.confidence, greaterThan(initialConfidence));
  });
}
