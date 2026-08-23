import '../cognitive/neura_cognitive_state.dart';
import 'neura_adaptive_plan_session.dart';

enum NeuraOutcomeAdaptationKind { reduceLoad, maintain, protectFocus }

class NeuraOutcomeAdaptation {
  final NeuraOutcomeAdaptationKind kind;
  final NeuraBandwidthMode recommendedMode;
  final int maxPrimaryActions;
  final bool suppressProactiveSuggestions;
  final double confidence;
  final List<String> reasons;

  NeuraOutcomeAdaptation({
    required this.kind,
    required this.recommendedMode,
    required this.maxPrimaryActions,
    required this.suppressProactiveSuggestions,
    required double confidence,
    List<String> reasons = const <String>[],
  })  : confidence = confidence.clamp(0.0, 1.0).toDouble(),
        reasons = List<String>.unmodifiable(reasons);
}

class NeuraAdaptiveOutcomeLoop {
  const NeuraAdaptiveOutcomeLoop();

  NeuraOutcomeAdaptation evaluate({
    required Iterable<NeuraPlanOutcomeReceipt> history,
    required NeuraCognitiveState currentState,
  }) {
    final all = history.toList(growable: false);
    final recent =
        all.length <= 5 ? all : all.sublist(all.length - 5, all.length);
    if (recent.isEmpty) {
      return NeuraOutcomeAdaptation(
        kind: NeuraOutcomeAdaptationKind.maintain,
        recommendedMode: currentState.mode,
        maxPrimaryActions: _defaultActionLimit(currentState.mode),
        suppressProactiveSuggestions:
            currentState.mode == NeuraBandwidthMode.deepFocus,
        confidence: 0.25,
        reasons: const <String>[
          'No completed Adaptive Intent sessions are available yet.',
        ],
      );
    }

    var completionTotal = 0.0;
    var effortTotal = 0.0;
    var satisfactionTotal = 0.0;
    var interruptionTotal = 0;
    var abandonedCount = 0;
    for (final outcome in recent) {
      completionTotal += outcome.completionRatio;
      effortTotal += outcome.perceivedEffort;
      satisfactionTotal += outcome.satisfaction;
      interruptionTotal += outcome.interruptionCount;
      if (outcome.status == NeuraPlanSessionStatus.abandoned) {
        abandonedCount += 1;
      }
    }

    final count = recent.length;
    final averageCompletion = completionTotal / count;
    final averageEffort = effortTotal / count;
    final averageSatisfaction = satisfactionTotal / count;
    final averageInterruptions = interruptionTotal / count;
    final confidence = (0.35 + count * 0.12).clamp(0.0, 0.95).toDouble();

    final overloaded = abandonedCount > 0 ||
        averageCompletion < 0.45 ||
        averageEffort > 0.75 ||
        averageInterruptions >= 4;
    if (overloaded) {
      final recovery = currentState.availableBandwidth < 0.40 ||
          currentState.cognitiveLoad > 0.75;
      return NeuraOutcomeAdaptation(
        kind: NeuraOutcomeAdaptationKind.reduceLoad,
        recommendedMode: recovery
            ? NeuraBandwidthMode.recovery
            : NeuraBandwidthMode.simplified,
        maxPrimaryActions: recovery ? 1 : 2,
        suppressProactiveSuggestions: true,
        confidence: confidence,
        reasons: <String>[
          if (abandonedCount > 0)
            'A recent session was abandoned before its local plan finished.',
          if (averageCompletion < 0.45)
            'Recent local-step completion was below 45 percent.',
          if (averageEffort > 0.75)
            'Recent sessions were reported as high effort.',
          if (averageInterruptions >= 4)
            'Recent sessions averaged four or more interruptions.',
        ],
      );
    }

    final lastTwo = recent.length < 2
        ? const <NeuraPlanOutcomeReceipt>[]
        : recent.sublist(recent.length - 2);
    final sustainedSuccess = lastTwo.length == 2 &&
        lastTwo.every(
          (outcome) =>
              outcome.completionRatio >= 0.80 &&
              outcome.satisfaction >= 0.65 &&
              outcome.perceivedEffort <= 0.70 &&
              outcome.status == NeuraPlanSessionStatus.completed,
        );
    if (sustainedSuccess &&
        currentState.mode != NeuraBandwidthMode.recovery &&
        currentState.availableBandwidth >= 0.60) {
      return NeuraOutcomeAdaptation(
        kind: NeuraOutcomeAdaptationKind.protectFocus,
        recommendedMode: NeuraBandwidthMode.deepFocus,
        maxPrimaryActions: 3,
        suppressProactiveSuggestions: true,
        confidence: confidence,
        reasons: const <String>[
          'Two recent sessions completed with strong satisfaction and manageable effort.',
          'Protecting one focused outcome is safer than adding more suggestions.',
        ],
      );
    }

    return NeuraOutcomeAdaptation(
      kind: NeuraOutcomeAdaptationKind.maintain,
      recommendedMode: currentState.mode,
      maxPrimaryActions: _defaultActionLimit(currentState.mode),
      suppressProactiveSuggestions:
          currentState.mode == NeuraBandwidthMode.deepFocus,
      confidence: confidence,
      reasons: <String>[
        'Recent outcomes do not justify a larger or smaller plan yet.',
        if (averageSatisfaction < 0.50)
          'Satisfaction is still mixed, so Neura keeps the current policy.',
      ],
    );
  }

  int _defaultActionLimit(NeuraBandwidthMode mode) {
    return switch (mode) {
      NeuraBandwidthMode.recovery => 1,
      NeuraBandwidthMode.simplified => 2,
      NeuraBandwidthMode.balanced => 3,
      NeuraBandwidthMode.deepFocus => 3,
    };
  }
}
