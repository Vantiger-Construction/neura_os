import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/relationships/models/neura_promise.dart';
import 'package:neuro_companion/relationships/services/promise_service.dart';

class _RecordingScheduler implements PromiseReminderScheduler {
  final scheduled = <String, DateTime>{};
  final cancelled = <String>[];

  @override
  Future<void> schedulePromiseReminder({
    required String promiseId,
    required String description,
    required DateTime dueAt,
  }) async {
    scheduled[promiseId] = dueAt;
  }

  @override
  Future<void> cancelPromiseReminder(String promiseId) async {
    cancelled.add(promiseId);
    scheduled.remove(promiseId);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('creating a promise with a due date schedules exactly one reminder',
      () async {
    final scheduler = _RecordingScheduler();
    final service = PromiseService.forTesting(scheduler: scheduler);
    final dueAt = DateTime.now().add(const Duration(days: 1));

    final promise =
        await service.create(description: 'Call mom', dueAt: dueAt);

    expect(scheduler.scheduled, {promise.id: dueAt});
    expect(scheduler.cancelled, isEmpty);
  });

  test('creating a promise without a due date schedules nothing', () async {
    final scheduler = _RecordingScheduler();
    final service = PromiseService.forTesting(scheduler: scheduler);

    await service.create(description: 'Something open-ended');

    expect(scheduler.scheduled, isEmpty);
  });

  test('completing a promise cancels its reminder', () async {
    final scheduler = _RecordingScheduler();
    final service = PromiseService.forTesting(scheduler: scheduler);
    final promise = await service.create(
      description: 'Water the plants',
      dueAt: DateTime.now().add(const Duration(hours: 2)),
    );

    await service.updateStatus(promise.id, PromiseStatus.completed);

    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, [promise.id]);
  });

  test('changing a due date reschedules rather than duplicating', () async {
    final scheduler = _RecordingScheduler();
    final service = PromiseService.forTesting(scheduler: scheduler);
    final firstDueAt = DateTime.now().add(const Duration(days: 1));
    final promise =
        await service.create(description: 'Send the report', dueAt: firstDueAt);

    final secondDueAt = DateTime.now().add(const Duration(days: 3));
    await service.update(promise.id, dueAt: secondDueAt);

    expect(scheduler.scheduled, {promise.id: secondDueAt});
  });

  test('clearing a due date cancels the reminder', () async {
    final scheduler = _RecordingScheduler();
    final service = PromiseService.forTesting(scheduler: scheduler);
    final promise = await service.create(
      description: 'Pick a date later',
      dueAt: DateTime.now().add(const Duration(days: 1)),
    );

    await service.update(promise.id, clearDueAt: true);

    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, [promise.id]);
  });

  test('disabling reminders globally suppresses scheduling the same way '
      'existing reminders are suppressed', () async {
    final scheduler = _RecordingScheduler();
    var remindersEnabled = true;
    final service = PromiseService.forTesting(
      scheduler: scheduler,
      remindersEnabled: () => remindersEnabled,
    );
    final promise = await service.create(
      description: 'Read that book',
      dueAt: DateTime.now().add(const Duration(days: 1)),
    );
    expect(scheduler.scheduled, contains(promise.id));

    remindersEnabled = false;
    await service.syncAllReminders();

    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, contains(promise.id));
  });
}
