import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/planning/neura_daily_plan.dart';

void main() {
  test('preview needs approval; edits invalidate approval and all progress',
      () {
    final plan = NeuraDailyPlan();
    addTearDown(plan.dispose);
    plan.preview('  Tidy room ', [' Desk ', '', 'Floor']);
    expect(plan.goal, 'Tidy room');
    expect(plan.steps, ['Desk', 'Floor']);
    expect(() => plan.complete(0, true), throwsStateError);
    plan.approve();
    plan.complete(0, true);
    plan.complete(0, true);
    expect(plan.completedCount, 1);
    plan.complete(0, false);
    expect(plan.completedCount, 0);
    plan.preview('Tidy room', ['Desk']);
    expect(plan.approved, false);
    expect(() => plan.complete(0, true), throwsStateError);
    expect(() => plan.steps.add('injected'), throwsUnsupportedError);
  });

  test('reject invalid plans and stale or invalid completion indexes', () {
    final plan = NeuraDailyPlan();
    addTearDown(plan.dispose);
    expect(plan.approve, throwsStateError);
    expect(() => plan.preview('', ['Step']), throwsArgumentError);
    expect(() => plan.preview('Goal', []), throwsArgumentError);
    expect(() => plan.preview('Goal', List.filled(9, 'Step')),
        throwsArgumentError);
    expect(() => plan.preview('Goal', ['x' * 161]), throwsArgumentError);
    plan.preview('Goal', ['Step']);
    plan.approve();
    expect(() => plan.complete(1, true), throwsStateError);
    plan.clear();
    expect(plan.goal, isEmpty);
    expect(plan.steps, isEmpty);
    expect(() => plan.complete(0, true), throwsStateError);
  });
}
