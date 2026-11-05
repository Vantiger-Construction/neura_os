import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/planning/neura_daily_plan.dart';
import 'package:neuro_companion/planning/neura_plan_templates.dart';

void main() {
  late NeuraDailyPlan plan;
  setUp(() {
    plan = NeuraDailyPlan()
      ..preview('Synthetic goal', ['First', 'Second', 'Third']);
    plan.approve();
    plan.complete(0, true);
    plan.complete(2, true);
  });
  tearDown(() => plan.dispose());

  test('all templates are bounded drafts with no approval or progress', () {
    for (final template in NeuraPlanTemplate.values) {
      plan.preview(template.goal, template.steps);
      expect(plan.approved, false);
      expect(plan.completedCount, 0);
      expect(plan.steps.length, inInclusiveRange(1, 8));
    }
  });

  test('editing resets only changed work and revokes approval', () {
    plan.editStep(0, 'A smaller first step');
    expect(plan.isComplete(0), false);
    expect(plan.isComplete(2), true);
    expect(plan.approved, false);
    expect(() => plan.complete(1, true), throwsStateError);
  });

  test('moving in either direction keeps completion attached to the step', () {
    plan.moveStep(0, 2);
    expect(plan.steps, ['Second', 'Third', 'First']);
    expect(
        [for (var i = 0; i < 3; i++) plan.isComplete(i)], [false, true, true]);
    plan.moveStep(2, 0);
    expect(plan.steps, ['First', 'Second', 'Third']);
    expect(
        [for (var i = 0; i < 3; i++) plan.isComplete(i)], [true, false, true]);
    expect(plan.approved, false);
  });

  test('remove shifts progress and undo restores content but not authority',
      () {
    plan.removeStep(0);
    expect(plan.steps, ['Second', 'Third']);
    expect(plan.isComplete(0), false);
    expect(plan.isComplete(1), true);
    plan.undoEdit();
    expect(plan.steps, ['First', 'Second', 'Third']);
    expect(plan.isComplete(0), true);
    expect(plan.isComplete(2), true);
    expect(plan.approved, false);
    expect(plan.canUndo, false);
  });

  test('add preserves progress and enforces the eight-step transfer bound', () {
    for (var i = 0; i < 5; i++) {
      plan.addStep('Extra $i');
    }
    expect(plan.completedCount, 2);
    expect(() => plan.addStep('Ninth'), throwsArgumentError);
    expect(() => plan.editStep(0, 'x' * 161), throwsArgumentError);
    expect(() => plan.editStep(0, 'Hidden\u0000text'), throwsArgumentError);
    expect(plan.steps, hasLength(8));
  });

  test('cannot remove the last step and invalid edits leave approval intact',
      () {
    plan.preview('One', ['Only']);
    plan.approve();
    expect(() => plan.removeStep(0), throwsArgumentError);
    expect(() => plan.moveStep(0, 1), throwsArgumentError);
    expect(() => plan.editStep(0, ''), throwsArgumentError);
    expect(plan.approved, true);
    expect(plan.canUndo, false);
  });

  test('clear and imported previews cannot resurrect an undo snapshot', () {
    plan.editStep(1, 'Changed');
    plan.clear();
    plan.undoEdit();
    expect(plan.steps, isEmpty);
    plan.preview('Next', ['Step']);
    plan.addStep('Another');
    plan.previewTransferred('Imported', ['Reviewed'], {});
    expect(plan.canUndo, false);
    expect(plan.approved, false);
  });

  test('recording new progress drops the old edit undo', () {
    plan.addStep('New');
    plan.approve();
    plan.complete(1, true);
    expect(plan.canUndo, false);
  });
}
