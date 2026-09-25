import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/action_plan.dart';
import 'package:neuro_companion/intelligence/approval_broker.dart';

void main() {
  NeuraActionPlan plan() => NeuraActionPlan(const <NeuraActionPlanStep>[
        NeuraActionPlanStep(actionId: 'a1', title: 'First reviewed action'),
        NeuraActionPlanStep(actionId: 'a2', title: 'Second reviewed action'),
      ]);

  test('advances only after the current action executes', () {
    final value = plan();
    value.recordOutcome(actionId: 'a1', status: NeuraApprovalStatus.approved);
    expect(value.nextStep!.actionId, 'a1');
    value.recordOutcome(actionId: 'a1', status: NeuraApprovalStatus.executed);
    expect(value.nextStep!.actionId, 'a2');
    expect(value.requiresApprovalForEveryStep, isTrue);
  });

  test('blocks instead of skipping a denied action', () {
    final value = plan();
    value.recordOutcome(
      actionId: 'a1',
      status: NeuraApprovalStatus.denied,
      reason: 'User declined.',
    );
    expect(value.state, NeuraActionPlanState.blocked);
    expect(value.nextStep, isNull);
    expect(value.blockedReason, 'User declined.');
  });

  test('rejects out-of-order action updates', () {
    final value = plan();
    expect(
      () => value.recordOutcome(
        actionId: 'a2',
        status: NeuraApprovalStatus.executed,
      ),
      throwsStateError,
    );
  });
}
