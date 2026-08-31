enum NeuraFuturePathGoal {
  fastest,
  safest,
  lowestCost,
  lowestEffort,
  mostReversible,
}

class NeuraPlanStep {
  const NeuraPlanStep({
    required this.id,
    required this.title,
    required this.estimatedDuration,
    required this.effort,
    required this.cost,
    required this.risk,
    required this.reversible,
    this.hasExternalEffect = false,
  });

  final String id;
  final String title;
  final Duration estimatedDuration;
  final double effort;
  final double cost;
  final double risk;
  final bool reversible;
  final bool hasExternalEffect;
}

class NeuraFuturePath {
  NeuraFuturePath({
    required this.goal,
    required Iterable<NeuraPlanStep> steps,
    required this.score,
    required this.requiresApproval,
  }) : steps = List<NeuraPlanStep>.unmodifiable(steps);

  final NeuraFuturePathGoal goal;
  final List<NeuraPlanStep> steps;
  final double score;
  final bool requiresApproval;

  /// Simulations are advice only. They cannot execute themselves.
  bool get executable => false;
}

class NeuraFuturePathsSimulator {
  const NeuraFuturePathsSimulator();

  List<NeuraFuturePath> simulate(Iterable<NeuraPlanStep> input) {
    final steps = List<NeuraPlanStep>.from(input);
    if (steps.isEmpty) {
      return const <NeuraFuturePath>[];
    }

    return [
      _path(NeuraFuturePathGoal.fastest, steps),
      _path(NeuraFuturePathGoal.safest, steps),
      _path(NeuraFuturePathGoal.lowestCost, steps),
      _path(NeuraFuturePathGoal.lowestEffort, steps),
      _path(NeuraFuturePathGoal.mostReversible, steps),
    ];
  }

  NeuraFuturePath _path(
    NeuraFuturePathGoal goal,
    List<NeuraPlanStep> source,
  ) {
    final ordered = List<NeuraPlanStep>.from(source)
      ..sort((a, b) {
        final scoreCompare = _stepScore(
          goal,
          a,
        ).compareTo(_stepScore(goal, b));
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.id.compareTo(b.id);
      });

    final averageScore =
        ordered.map((step) => _stepScore(goal, step)).reduce((a, b) => a + b) /
            ordered.length;

    return NeuraFuturePath(
      goal: goal,
      steps: ordered,
      score: averageScore,
      requiresApproval: ordered.any(
        (step) => step.hasExternalEffect || !step.reversible,
      ),
    );
  }

  double _stepScore(NeuraFuturePathGoal goal, NeuraPlanStep step) {
    final durationMinutes =
        step.estimatedDuration.inSeconds / Duration.secondsPerMinute;

    switch (goal) {
      case NeuraFuturePathGoal.fastest:
        return durationMinutes;
      case NeuraFuturePathGoal.safest:
        return (step.risk * 100) +
            (step.hasExternalEffect ? 50 : 0) +
            (step.reversible ? 0 : 25);
      case NeuraFuturePathGoal.lowestCost:
        return step.cost;
      case NeuraFuturePathGoal.lowestEffort:
        return step.effort;
      case NeuraFuturePathGoal.mostReversible:
        return (step.reversible ? 0 : 100) +
            (step.hasExternalEffect ? 25 : 0) +
            step.risk;
    }
  }
}
