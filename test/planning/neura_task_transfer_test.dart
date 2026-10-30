import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/planning/neura_task_transfer.dart';
import 'package:neuro_companion/planning/neura_daily_plan.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30);
  NeuraTaskSnapshot snapshot() => NeuraTaskSnapshot(
      goal: 'Prepare tomorrow',
      steps: ['Pack bag', 'Choose first task'],
      completed: {0});

  test(
      'authenticated round trip transfers only reviewed task state, never approval',
      () async {
    final sealed = await NeuraTaskTransfer.seal(snapshot(), now: now);
    expect(utf8.decode(base64Url.decode(sealed.packet), allowMalformed: true),
        isNot(contains('Pack bag')));
    final opened =
        await NeuraTaskTransfer.open(sealed.packet, sealed.key, now: now);
    expect(opened.goal, 'Prepare tomorrow');
    expect(opened.completed, {0});
    final plan = NeuraDailyPlan();
    addTearDown(plan.dispose);
    plan.previewTransferred(opened.goal, opened.steps, opened.completed);
    expect(plan.approved, false);
    expect(plan.nextStepIndex, 1);
    expect(() => plan.complete(1, true), throwsStateError);
    plan.approve();
    plan.complete(1, true);
    expect(plan.nextStepIndex, isNull);
  });
  test(
      'wrong key, modified ciphertext, expired and future packets are rejected',
      () async {
    final sealed = await NeuraTaskTransfer.seal(snapshot(), now: now);
    final other = await NeuraTaskTransfer.seal(snapshot(), now: now);
    await expectLater(
        NeuraTaskTransfer.open(sealed.packet, other.key, now: now),
        throwsA(anything));
    final bytes = base64Url.decode(sealed.packet)..[20] ^= 1;
    await expectLater(
        NeuraTaskTransfer.open(base64UrlEncode(bytes), sealed.key, now: now),
        throwsA(anything));
    await expectLater(
        NeuraTaskTransfer.open(sealed.packet, sealed.key,
            now: now.add(const Duration(minutes: 30))),
        throwsFormatException);
    await expectLater(
        NeuraTaskTransfer.open(sealed.packet, sealed.key,
            now: now.subtract(const Duration(seconds: 1))),
        throwsFormatException);
  });
  test('oversized input and invalid progress are rejected', () async {
    await expectLater(
        NeuraTaskTransfer.open('a' * 16001, 'b' * 44), throwsFormatException);
    expect(
        () => NeuraTaskSnapshot(goal: 'Goal', steps: ['Step'], completed: {1}),
        throwsFormatException);
    expect(
        () => NeuraTaskSnapshot(
            goal: 'Goal', steps: ['Line\nbreak'], completed: {}),
        throwsFormatException);
  });
  test('smaller step preserves completed work and requires fresh approval', () {
    final plan = NeuraDailyPlan();
    addTearDown(plan.dispose);
    plan.preview('Tidy desk', ['Clear cups', 'Sort papers']);
    plan.approve();
    plan.complete(0, true);
    plan.pause(true);
    expect(() => plan.complete(1, true), throwsStateError);
    plan.makeCurrentStepSmaller('Sort just one paper');
    expect(plan.isComplete(0), true);
    expect(plan.approved, false);
    expect(plan.steps[1], 'Sort just one paper');
    expect(() => plan.complete(1, true), throwsStateError);
    plan.approve();
    plan.complete(1, true);
    expect(plan.completedCount, 2);
    plan.clear();
    expect(plan.steps, isEmpty);
    expect(plan.completedCount, 0);
  });
}
