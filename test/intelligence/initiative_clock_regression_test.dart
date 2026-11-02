import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/initiative_source.dart';
import 'package:neuro_companion/intelligence/routine_model.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tzdata.initializeTimeZones();
  const source = NeuraInitiativeSource();

  NeuraRoutineModel history(tz.Location zone) {
    var routine = NeuraRoutineModel.empty();
    for (var day = 1; day <= 20; day++) {
      routine = routine
          .recordOpen(tz.TZDateTime(zone, 2026, 10, day, 9))
          .recordOpen(tz.TZDateTime(zone, 2026, 10, day, 20));
    }
    return routine;
  }

  test('clock rollback to another late-night hour produces no check-in', () {
    final zone = tz.getLocation('America/Chicago');
    final routine =
        history(zone).recordOpen(tz.TZDateTime(zone, 2026, 10, 21, 4));
    expect(
      source.scan(routine: routine, now: tz.TZDateTime(zone, 2026, 10, 21, 2)),
      isEmpty,
    );
  });

  test('timezone travel cannot classify old local hours as unusual', () {
    final routine = history(tz.getLocation('America/Chicago'));
    final reloaded = NeuraRoutineModel.fromJson(routine.toJson());
    final now = tz.TZDateTime(tz.getLocation('Europe/London'), 2026, 10, 21, 3);
    expect(source.scan(routine: reloaded, now: now), isEmpty);
    expect(reloaded.recordOpen(now).totalCount, 1);
  });

  test('a daylight-saving offset change starts a fresh local-hour baseline',
      () {
    final zone = tz.getLocation('America/Chicago');
    final routine = history(zone);
    final afterDst = tz.TZDateTime(zone, 2026, 11, 1, 2, 30);
    expect(routine.matchesTimeZone(afterDst), isFalse);
    expect(source.scan(routine: routine, now: afterDst), isEmpty);
    final fresh = routine.recordOpen(afterDst);
    expect(fresh.totalCount, 1);
    expect(fresh.distinctDays, 1);
    expect(fresh.pendingArrivalFrom, isNull);
  });
}
