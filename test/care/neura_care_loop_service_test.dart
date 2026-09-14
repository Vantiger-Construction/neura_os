import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/care/models/neura_care_plan.dart';
import 'package:neuro_companion/care/services/neura_care_loop_service.dart';

void main() {
  const service = NeuraCareLoopService();

  test('explicit safety concern always overrides routine self-care', () {
    final plan = service.buildPlan(
      const NeuraCareCheckIn(
        mood0to10: 8,
        energy0to10: 8,
        overwhelm0to10: 1,
        need: NeuraCareNeed.focus,
        feelsUnsafe: true,
      ),
    );

    expect(plan.requiresImmediateSupport, isTrue);
    expect(
      plan.primaryAction.kind,
      NeuraCareActionKind.immediateSupport,
    );
  });

  test('high overwhelm stabilizes before the requested task', () {
    final plan = service.buildPlan(
      const NeuraCareCheckIn(
        mood0to10: 5,
        energy0to10: 5,
        overwhelm0to10: 9,
        need: NeuraCareNeed.focus,
      ),
    );

    expect(plan.primaryAction.kind, NeuraCareActionKind.grounding);
    expect(plan.requiresImmediateSupport, isFalse);
  });

  test('very low energy makes a focus request smaller', () {
    final plan = service.buildPlan(
      const NeuraCareCheckIn(
        mood0to10: 5,
        energy0to10: 2,
        overwhelm0to10: 4,
        need: NeuraCareNeed.focus,
      ),
    );

    expect(plan.primaryAction.kind, NeuraCareActionKind.rest);
  });

  test('moderate check-in honors the need selected by the person', () {
    final plan = service.buildPlan(
      const NeuraCareCheckIn(
        mood0to10: 6,
        energy0to10: 6,
        overwhelm0to10: 4,
        need: NeuraCareNeed.connect,
      ),
    );

    expect(plan.primaryAction.kind, NeuraCareActionKind.connection);
  });

  test('plan stays bounded to one action and one alternative', () {
    final plan = service.buildPlan(
      const NeuraCareCheckIn(
        mood0to10: 3,
        energy0to10: 4,
        overwhelm0to10: 6,
        need: NeuraCareNeed.rest,
      ),
    );

    expect(plan.primaryAction.id, isNot(plan.alternativeAction.id));
    expect(plan.primaryAction.guidance, isNotEmpty);
    expect(plan.alternativeAction.guidance, isNotEmpty);
  });
}

