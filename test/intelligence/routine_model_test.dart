import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/routine_model.dart';

void main() {
  // 2026-10-05 is a Monday.
  // A stable zone keeps histogram-cap tests independent of seasonal DST.
  final monday9am = DateTime.utc(2026, 10, 5, 9, 15);

  group('NeuraRoutineModel.recordOpen', () {
    test('counts an open in its hour-of-week slot and remembers the day', () {
      final model = NeuraRoutineModel.empty().recordOpen(monday9am);

      expect(model.totalCount, 1);
      expect(model.hourOfWeekCounts[NeuraRoutineModel.slotFor(monday9am)], 1);
      expect(NeuraRoutineModel.slotFor(monday9am), 9);
      expect(model.activeDays, ['2026-10-05']);
      expect(model.lastSeenAt, monday9am);
    });

    test('repeated opens in the same clock hour count once', () {
      final model = NeuraRoutineModel.empty()
          .recordOpen(monday9am)
          .recordOpen(monday9am.add(const Duration(minutes: 20)))
          .recordOpen(monday9am.add(const Duration(minutes: 40)));

      expect(model.totalCount, 1);
      expect(model.lastSeenAt, monday9am.add(const Duration(minutes: 40)));
    });

    test('a new hour or day counts again', () {
      final model = NeuraRoutineModel.empty()
          .recordOpen(monday9am)
          .recordOpen(monday9am.add(const Duration(hours: 1)))
          .recordOpen(monday9am.add(const Duration(days: 1)));

      expect(model.totalCount, 3);
      expect(model.distinctDays, 2);
    });

    test('ignores a clock that moved backwards', () {
      final model = NeuraRoutineModel.empty().recordOpen(monday9am);
      final after = model.recordOpen(
        monday9am.subtract(const Duration(hours: 5)),
      );

      expect(identical(after, model), isTrue);
    });

    test('halves the histogram once it outgrows the cap', () {
      var model = NeuraRoutineModel.empty();
      var at = monday9am;
      for (var i = 0; i <= NeuraRoutineModel.maxTotalCount; i++) {
        model = model.recordOpen(at);
        at = at.add(const Duration(hours: 1));
      }

      expect(
        model.totalCount,
        lessThanOrEqualTo(NeuraRoutineModel.maxTotalCount ~/ 2 + 1),
      );
      expect(
        model.distinctDays,
        lessThanOrEqualTo(NeuraRoutineModel.maxActiveDays),
      );
    });

    test('keeps only the most recent active days', () {
      var model = NeuraRoutineModel.empty();
      for (var day = 0; day < NeuraRoutineModel.maxActiveDays + 10; day++) {
        model = model.recordOpen(monday9am.add(Duration(days: day)));
      }

      expect(model.distinctDays, NeuraRoutineModel.maxActiveDays);
      expect(
        model.activeDays.last,
        NeuraRoutineModel.dayKey(
          monday9am.add(
            const Duration(days: NeuraRoutineModel.maxActiveDays + 9),
          ),
        ),
      );
    });
  });

  group('NeuraRoutineModel.shareAround', () {
    test('is zero with no history', () {
      expect(NeuraRoutineModel.empty().shareAround(monday9am), 0);
    });

    test('includes the neighbouring hours, wrapping across the week', () {
      // Sunday 23:00 sits next to Monday 00:00 across the week boundary.
      final sundayLate = DateTime(2026, 10, 11, 23, 30);
      final mondayMidnight = DateTime(2026, 10, 12, 0, 10);
      final model = NeuraRoutineModel.empty().recordOpen(sundayLate);

      expect(model.shareAround(mondayMidnight), 1.0);
      expect(model.shareAround(monday9am), 0);
    });
  });

  group('NeuraRoutineModel JSON', () {
    test('round-trips through jsonEncode', () {
      final model = NeuraRoutineModel.empty()
          .recordOpen(monday9am)
          .recordOpen(monday9am.add(const Duration(days: 2, hours: 3)));
      final decoded = NeuraRoutineModel.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(model.toJson())) as Map,
        ),
      );

      expect(decoded.hourOfWeekCounts, model.hourOfWeekCounts);
      expect(decoded.activeDays, model.activeDays);
      expect(decoded.lastSeenAt!.isAtSameMomentAs(model.lastSeenAt!), isTrue);
      expect(decoded.timeZoneId, model.timeZoneId);
    });

    test('falls back to empty on unknown versions or malformed fields', () {
      final unknown = NeuraRoutineModel.fromJson(const {'v': 99});
      expect(unknown.totalCount, 0);
      expect(unknown.lastSeenAt, isNull);

      final malformed = NeuraRoutineModel.fromJson({
        'v': 2,
        'zone': NeuraRoutineModel.zoneFor(monday9am),
        'hour_of_week': [1, 2, 3],
        'days': ['not-a-day', 7, '2026-10-05'],
        'last_seen_ms': 'yesterday',
      });
      expect(
        malformed.hourOfWeekCounts,
        hasLength(NeuraRoutineModel.slotCount),
      );
      expect(malformed.totalCount, 0);
      expect(malformed.activeDays, ['2026-10-05']);
      expect(malformed.lastSeenAt, isNull);
    });

    test('untagged legacy history cannot be used for inference', () {
      final legacy = NeuraRoutineModel.empty().recordOpen(monday9am).toJson()
        ..['v'] = 1
        ..remove('zone');
      expect(NeuraRoutineModel.fromJson(legacy).totalCount, 0);
    });

    test(
      'a reloaded UTC timestamp still deduplicates its local clock hour',
      () {
        final model = NeuraRoutineModel.empty().recordOpen(monday9am);
        final reloaded = NeuraRoutineModel.fromJson(model.toJson());
        expect(
          reloaded
              .recordOpen(monday9am.add(const Duration(minutes: 20)))
              .totalCount,
          1,
        );
      },
    );

    test('arrival survives recorded opens and reload until acknowledged', () {
      final returnedAt = monday9am.add(const Duration(days: 5));
      final model = NeuraRoutineModel.empty()
          .recordOpen(monday9am)
          .recordOpen(returnedAt)
          .recordOpen(returnedAt.add(const Duration(hours: 2)));
      final reloaded = NeuraRoutineModel.fromJson(model.toJson());
      expect(reloaded.pendingArrivalFrom!.isAtSameMomentAs(monday9am), isTrue);
      expect(reloaded.pendingArrivalAt!.isAtSameMomentAs(returnedAt), isTrue);
      expect(
        reloaded.acknowledgeArrival('other').pendingArrivalFrom,
        isNotNull,
      );
      expect(
        reloaded
            .acknowledgeArrival(
              'initiative.arrival:${monday9am.millisecondsSinceEpoch}',
            )
            .pendingArrivalFrom,
        isNull,
      );
    });

    test('out-of-range timestamps are ignored without throwing', () {
      final json = NeuraRoutineModel.empty().recordOpen(monday9am).toJson()
        ..['last_seen_ms'] = 9e100;
      expect(NeuraRoutineModel.fromJson(json).lastSeenAt, isNull);
    });

    test('clamps negative counts to zero', () {
      final counts = List<int>.filled(NeuraRoutineModel.slotCount, 0);
      counts[3] = -4;
      counts[4] = 2;
      final model = NeuraRoutineModel(hourOfWeekCounts: counts);

      expect(model.totalCount, 2);
    });
  });

  group('NeuraRoutineModel late nights', () {
    // Local times: night keys are about the user's own evenings.
    DateTime at(int day, int hour, [int minute = 0]) =>
        DateTime(2026, 10, day, hour, minute);

    test('a visit after midnight belongs to the previous evening', () {
      final model = NeuraRoutineModel.empty()
          .recordOpen(at(6, 0, 30))
          .recordOpen(at(6, 4, 59))
          .recordOpen(at(6, 5))
          .recordOpen(at(6, 23, 30));
      expect(model.lateNights, ['2026-10-05']);
      expect(NeuraRoutineModel.nightKeyFor(at(1, 2)), '2026-09-30');
      expect(NeuraRoutineModel.nightKeyFor(at(1, 5)), isNull);
    });

    test('keeps only the most recent nights', () {
      var model = NeuraRoutineModel.empty();
      for (var day = 1; day <= 20; day++) {
        model = model.recordOpen(at(day, 1));
      }
      expect(model.lateNights, hasLength(NeuraRoutineModel.maxLateNights));
      expect(model.lateNights.first, '2026-10-06');
      expect(model.lateNights.last, '2026-10-19');
    });

    test('counts the previous seven nights and never tonight', () {
      var model = NeuraRoutineModel.empty();
      // Nights of Oct 3, 5, 9 and 11.
      for (final day in [4, 6, 10, 12]) {
        model = model.recordOpen(at(day, 1));
      }
      // Evening of Oct 12: window is the nights of Oct 5..11.
      expect(model.lateNightsBefore(at(12, 21)), 3);
      expect(model.lateNightsBefore(at(12, 21), nights: 2), 1);
      // Evening of Oct 11: the Oct 11 night has not started yet.
      expect(model.lateNightsBefore(at(11, 21)), 2);
    });

    test('round-trips through JSON and keeps older v2 history', () {
      final model = NeuraRoutineModel.empty()
          .recordOpen(at(6, 1))
          .recordOpen(at(6, 21))
          .acknowledgeWindDown('initiative.wind_down:2026-10-06');
      final restored = NeuraRoutineModel.fromJson(
        jsonDecode(jsonEncode(model.toJson())) as Map<String, Object?>,
      );
      expect(restored.lateNights, ['2026-10-05']);
      expect(restored.windDownOfferedDay, '2026-10-06');

      final older = Map<String, Object?>.of(model.toJson())
        ..remove('late_nights')
        ..remove('wind_down_day');
      final upgraded = NeuraRoutineModel.fromJson(older);
      expect(upgraded.totalCount, model.totalCount);
      expect(upgraded.lateNights, isEmpty);
      expect(upgraded.windDownOfferedDay, isNull);
    });

    test('malformed late-night fields are dropped, not guessed', () {
      final json = NeuraRoutineModel.empty().recordOpen(at(6, 1)).toJson();
      json['late_nights'] = ['2026-10-05', 'yesterday', 7, null];
      json['wind_down_day'] = 'tonight';
      final model = NeuraRoutineModel.fromJson(json);
      expect(model.lateNights, ['2026-10-05']);
      expect(model.windDownOfferedDay, isNull);
    });

    test('wind-down acknowledgement and cooldown arithmetic', () {
      final model = NeuraRoutineModel.empty().recordOpen(at(6, 21));
      expect(model.daysSinceWindDownOffer(at(6, 21)), isNull);
      expect(
        model.acknowledgeWindDown('initiative.arrival:1').windDownOfferedDay,
        isNull,
      );
      expect(
        model.acknowledgeWindDown('initiative.wind_down:soon'),
        same(model),
      );
      final acked =
          model.acknowledgeWindDown('initiative.wind_down:2026-10-06');
      expect(acked.daysSinceWindDownOffer(at(6, 23)), 0);
      expect(acked.daysSinceWindDownOffer(at(13, 20)), 7);
      // Later opens keep the cooldown and the late nights.
      final later = acked.recordOpen(at(7, 1));
      expect(later.windDownOfferedDay, '2026-10-06');
      expect(later.lateNights, ['2026-10-06']);
      expect(
        later.acknowledgeArrival('initiative.arrival:0').lateNights,
        later.lateNights,
      );
    });
  });
}
