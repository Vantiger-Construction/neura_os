import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/living_intelligence/future_paths_simulator.dart';

void main() {
  const simulator = NeuraFuturePathsSimulator();

  test('simulate returns nothing for an empty plan', () {
    expect(simulator.simulate(const []), isEmpty);
  });

  test('simulate returns exactly one path per goal', () {
    final steps = [
      const NeuraPlanStep(
        id: 'a',
        title: 'A',
        estimatedDuration: Duration(minutes: 10),
        effort: 0.2,
        cost: 0.1,
        risk: 0.1,
        reversible: true,
      ),
      const NeuraPlanStep(
        id: 'b',
        title: 'B',
        estimatedDuration: Duration(minutes: 30),
        effort: 0.8,
        cost: 0.5,
        risk: 0.4,
        reversible: false,
      ),
    ];

    final paths = simulator.simulate(steps);

    expect(paths, hasLength(NeuraFuturePathGoal.values.length));
    expect(
      paths.map((p) => p.goal).toSet(),
      NeuraFuturePathGoal.values.toSet(),
    );
    for (final path in paths) {
      expect(path.steps, hasLength(2));
      expect(path.executable, isFalse);
    }
  });

  test('fastest orders by shortest duration first', () {
    final steps = [
      const NeuraPlanStep(
        id: 'slow',
        title: 'Slow',
        estimatedDuration: Duration(hours: 2),
        effort: 0.1,
        cost: 0.1,
        risk: 0.1,
        reversible: true,
      ),
      const NeuraPlanStep(
        id: 'fast',
        title: 'Fast',
        estimatedDuration: Duration(minutes: 5),
        effort: 0.1,
        cost: 0.1,
        risk: 0.1,
        reversible: true,
      ),
    ];

    final path = simulator
        .simulate(steps)
        .firstWhere((p) => p.goal == NeuraFuturePathGoal.fastest);

    expect(path.steps.map((s) => s.id), ['fast', 'slow']);
  });

  test('safest penalizes external effects and irreversibility', () {
    final steps = [
      const NeuraPlanStep(
        id: 'risky',
        title: 'Risky',
        estimatedDuration: Duration(minutes: 5),
        effort: 0.1,
        cost: 0.1,
        risk: 0.05,
        reversible: false,
        hasExternalEffect: true,
      ),
      const NeuraPlanStep(
        id: 'careful',
        title: 'Careful',
        estimatedDuration: Duration(minutes: 5),
        effort: 0.1,
        cost: 0.1,
        risk: 0.05,
        reversible: true,
      ),
    ];

    final path = simulator
        .simulate(steps)
        .firstWhere((p) => p.goal == NeuraFuturePathGoal.safest);

    expect(path.steps.map((s) => s.id), ['careful', 'risky']);
    expect(path.requiresApproval, isTrue);
  });

  test('mostReversible orders reversible steps ahead of irreversible ones', () {
    final steps = [
      const NeuraPlanStep(
        id: 'permanent',
        title: 'Permanent',
        estimatedDuration: Duration(minutes: 5),
        effort: 0.1,
        cost: 0.1,
        risk: 0.1,
        reversible: false,
      ),
      const NeuraPlanStep(
        id: 'undoable',
        title: 'Undoable',
        estimatedDuration: Duration(minutes: 5),
        effort: 0.1,
        cost: 0.1,
        risk: 0.1,
        reversible: true,
      ),
    ];

    final path = simulator
        .simulate(steps)
        .firstWhere((p) => p.goal == NeuraFuturePathGoal.mostReversible);

    expect(path.steps.map((s) => s.id), ['undoable', 'permanent']);
  });

  test(
      'requiresApproval is false when every step is reversible with no '
      'external effect', () {
    final steps = [
      const NeuraPlanStep(
        id: 'a',
        title: 'A',
        estimatedDuration: Duration(minutes: 5),
        effort: 0.1,
        cost: 0.1,
        risk: 0.1,
        reversible: true,
      ),
    ];

    for (final path in simulator.simulate(steps)) {
      expect(path.requiresApproval, isFalse);
    }
  });
}
