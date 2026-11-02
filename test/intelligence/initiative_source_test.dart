import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/autonomy_kernel.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/initiative_source.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/intelligence/routine_model.dart';

void main() {
  const source = NeuraInitiativeSource();
  // 2026-10-05 is a Monday.
  final start = DateTime(2026, 10, 5);

  /// [days] days of a steady routine: 09:05 and 20:30 every day, plus 02:30
  /// when [nightOwl] is set. Opens are recorded in time order because the
  /// model ignores a clock that moves backwards.
  NeuraRoutineModel steadyRoutine({int days = 20, bool nightOwl = false}) {
    var model = NeuraRoutineModel.empty();
    for (var day = 0; day < days; day++) {
      final date = DateTime(start.year, start.month, start.day + day);
      if (nightOwl) {
        model = model.recordOpen(
          DateTime(date.year, date.month, date.day, 2, 30),
        );
      }
      model = model
          .recordOpen(DateTime(date.year, date.month, date.day, 9, 5))
          .recordOpen(DateTime(date.year, date.month, date.day, 20, 30));
    }
    return model;
  }

  NeuraIntelligenceCandidate? only(
    List<NeuraIntelligenceCandidate> candidates,
    String specialistId,
  ) {
    final matches = candidates.where((c) => c.specialistId == specialistId);
    return matches.isEmpty ? null : matches.single;
  }

  group('arrival', () {
    test('welcomes the user back after a long absence', () {
      final lastSeen = DateTime(2026, 10, 10, 9);
      final routine = NeuraRoutineModel.empty().recordOpen(lastSeen);
      final now = lastSeen.add(const Duration(days: 5, hours: 2));

      final arrival = only(
        source.scan(routine: routine, now: now),
        NeuraInitiativeSource.arrivalSpecialist,
      );

      expect(arrival, isNotNull);
      expect(arrival!.title, 'Welcome back');
      expect(arrival.body, contains('5 days'));
      expect(
        arrival.capabilityId,
        NeuraCapabilityRegistry.surfaceSuggestion,
      );
      expect(
        arrival.payload[NeuraInitiativeSource.kindKey],
        NeuraInitiativeSource.arrivalKind,
      );
      expect(arrival.evidence.single.sensitivity, NeuraSensitivity.routine);
    });

    test('stays quiet for short gaps, first runs, and clock skew', () {
      final lastSeen = DateTime(2026, 10, 10, 9);
      final routine = NeuraRoutineModel.empty().recordOpen(lastSeen);

      expect(
        only(
          source.scan(
            routine: routine,
            now: lastSeen.add(const Duration(days: 2)),
          ),
          NeuraInitiativeSource.arrivalSpecialist,
        ),
        isNull,
      );
      expect(
        source.scan(routine: NeuraRoutineModel.empty(), now: lastSeen),
        isEmpty,
      );
      expect(
        only(
          source.scan(
            routine: routine,
            now: lastSeen.subtract(const Duration(days: 9)),
          ),
          NeuraInitiativeSource.arrivalSpecialist,
        ),
        isNull,
      );
    });

    test('one absence yields one stable candidate id', () {
      final lastSeen = DateTime(2026, 10, 10, 9);
      final routine = NeuraRoutineModel.empty().recordOpen(lastSeen);
      final first = only(
        source.scan(routine: routine, now: DateTime(2026, 10, 16, 8)),
        NeuraInitiativeSource.arrivalSpecialist,
      );
      final second = only(
        source.scan(routine: routine, now: DateTime(2026, 10, 16, 8, 30)),
        NeuraInitiativeSource.arrivalSpecialist,
      );

      expect(first!.id, second!.id);
    });
  });

  group('routine shift', () {
    test('checks in on a late-night visit outside the usual routine', () {
      final routine = steadyRoutine();
      final lateNight = DateTime(2026, 10, 25, 2, 40);

      final shift = only(
        source.scan(routine: routine, now: lateNight),
        NeuraInitiativeSource.routineShiftSpecialist,
      );

      expect(shift, isNotNull);
      expect(shift!.title, 'Up later than usual');
      expect(
        shift.payload[NeuraInitiativeSource.kindKey],
        NeuraInitiativeSource.routineShiftKind,
      );
      expect(shift.evidence.single.sensitivity, NeuraSensitivity.personal);
      expect(shift.confidence, inInclusiveRange(0.6, 0.85));
    });

    test('needs enough history before calling an hour unusual', () {
      final routine = steadyRoutine(days: 5);

      expect(
        only(
          source.scan(routine: routine, now: DateTime(2026, 10, 25, 2, 40)),
          NeuraInitiativeSource.routineShiftSpecialist,
        ),
        isNull,
      );
    });

    test('ignores unusual hours outside the late-night window', () {
      final routine = steadyRoutine();

      expect(
        only(
          source.scan(routine: routine, now: DateTime(2026, 10, 25, 15)),
          NeuraInitiativeSource.routineShiftSpecialist,
        ),
        isNull,
      );
    });

    test('does not repeat within the same hour', () {
      final lateNight = DateTime(2026, 10, 25, 2, 10);
      final routine = steadyRoutine().recordOpen(lateNight);

      expect(
        only(
          source.scan(
            routine: routine,
            now: lateNight.add(const Duration(minutes: 30)),
          ),
          NeuraInitiativeSource.routineShiftSpecialist,
        ),
        isNull,
      );
    });

    test('a habitual late-night visitor is not "unusual"', () {
      final routine = steadyRoutine(nightOwl: true);

      expect(
        only(
          source.scan(routine: routine, now: DateTime(2026, 10, 25, 2, 40)),
          NeuraInitiativeSource.routineShiftSpecialist,
        ),
        isNull,
      );
    });
  });

  group('through the Autonomy Kernel', () {
    NeuraAutonomyPolicy policy({String? roomId}) => NeuraAutonomyPolicy(
          enabled: true,
          allowSensitiveSignals: false,
          maxDailySuggestions: 5,
          suggestionsToday: 0,
          suggestionsLastHour: 0,
          focusMode: 'normal',
          safeMode: false,
          recentlyDeclined: false,
          roomId: roomId,
        );

    test('both initiative candidates clear the kernel score bar', () {
      final kernel = NeuraAutonomyKernel();
      final lateNight = DateTime(2026, 10, 25, 2, 40);
      final candidates = [
        ...source.scan(
          routine: NeuraRoutineModel.empty().recordOpen(
            lateNight.subtract(const Duration(days: 4)),
          ),
          now: lateNight,
        ),
        ...source.scan(routine: steadyRoutine(), now: lateNight),
      ];
      expect(
        candidates.map((c) => c.specialistId).toSet(),
        {
          NeuraInitiativeSource.arrivalSpecialist,
          NeuraInitiativeSource.routineShiftSpecialist,
        },
      );

      for (final candidate in candidates) {
        final receipt = kernel.evaluate(
          candidate: candidate,
          policy: policy(),
          now: lateNight,
        );
        expect(
          receipt.outcome,
          NeuraDecisionOutcome.allow,
          reason: '${candidate.specialistId}: ${receipt.reasons}',
        );
      }
    });

    test('a private room keeps the welcome back silent', () {
      final lastSeen = DateTime(2026, 10, 10, 9);
      final now = DateTime(2026, 10, 16, 9);
      final arrival = source
          .scan(
            routine: NeuraRoutineModel.empty().recordOpen(lastSeen),
            now: now,
          )
          .single;

      final receipt = NeuraAutonomyKernel().evaluate(
        candidate: arrival,
        policy: policy(roomId: 'reflection_bay'),
        now: now,
      );

      expect(receipt.outcome, NeuraDecisionOutcome.suppressed);
      expect(receipt.reasons.join(' '), contains('private room'));
    });
  });
}
