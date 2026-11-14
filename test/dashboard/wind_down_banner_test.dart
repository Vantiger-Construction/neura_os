import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/dashboard/proactive_banner_service.dart';
import 'package:neuro_companion/intelligence/initiative_source.dart';
import 'package:neuro_companion/intelligence/neura_intelligence_controller.dart';
import 'package:neuro_companion/intelligence/routine_model.dart';
import 'package:neuro_companion/modules/human/human_prefs.dart';
import 'package:neuro_companion/modules/human/human_prefs_controller.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/modules/focus/focus_controller.dart';
import 'package:neuro_companion/src/modules/focus/focus_mode.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const routineKey = 'neura.initiative.routine.v1';
  final controller = NeuraIntelligenceController.instance;
  late DataWipeFixture fixture;
  late ProactiveBannerService service;
  late DateTime now;

  setUp(() async {
    fixture = await DataWipeFixture.create();
    // Synthetic history in UTC, so night keys don't depend on the runner.
    now = DateTime.utc(2026, 10, 29, 21);
    controller.resetForTesting();
    HumanPrefsController.instance.prefs.value = HumanPrefs.defaults;
    SafeBoot.instance.safeMode.value = false;
    FocusController.instance.state.value = FocusState(
      mode: FocusMode.off,
      startedAt: now.subtract(const Duration(days: 60)),
    );
    service = ProactiveBannerService.forTesting(clock: () => now);
    addTearDown(service.disposeForTesting);
    var routine = NeuraRoutineModel.empty();
    for (final day in [26, 27, 28]) {
      routine = routine.recordOpen(DateTime.utc(2026, 10, day, 1, 30));
    }
    routine = routine.recordOpen(DateTime.utc(2026, 10, 29, 9));
    await NeuraPrefsCache.prefs.setString(
      routineKey,
      jsonEncode(routine.toJson()),
    );
  });

  NeuraRoutineModel savedRoutine() {
    final raw = NeuraPrefsCache.prefs.getString(routineKey)!;
    return NeuraRoutineModel.fromJson(
      Map<String, Object?>.from(jsonDecode(raw) as Map),
    );
  }

  test('a shown wind-down offer starts a saved weekly cooldown', () async {
    await fixture.run(() async {
      final banner = await service.maybeGetBannerOnAppOpen();
      expect(
        banner?.candidate.specialistId,
        NeuraInitiativeSource.windDownSpecialist,
      );
      expect(banner!.kind, ProactiveBannerKind.focus);
      await service.recordShown(banner);

      final saved = savedRoutine();
      expect(saved.windDownOfferedDay, '2026-10-29');
      // The next evening still has three late nights in its window, so only
      // the saved cooldown keeps the offer away.
      final offers = const NeuraInitiativeSource().scan(
        routine: saved,
        now: DateTime.utc(2026, 10, 30, 21),
      );
      expect(
        offers.map((candidate) => candidate.specialistId),
        isNot(contains(NeuraInitiativeSource.windDownSpecialist)),
      );
      fixture.expectIsolation();
    });
  });

  test('an offer that never reaches a frame does not start the cooldown',
      () async {
    await fixture.run(() async {
      final banner = await service.maybeGetBannerOnAppOpen();
      expect(banner, isNotNull);
      service.releaseUnshown(banner!);
      expect(savedRoutine().windDownOfferedDay, isNull);
      fixture.expectIsolation();
    });
  });

  test('learning disabled keeps late-night history out of candidates',
      () async {
    await fixture.run(() async {
      HumanPrefsController.instance.prefs.value =
          HumanPrefs.defaults.copyWith(allowLearning: false);
      expect(await service.maybeGetBannerOnAppOpen(), isNull);
      const windDown = NeuraInitiativeSource.windDownSpecialist;
      expect(
        controller.records.where(
          (record) => record.receipt.specialistId == windDown,
        ),
        isEmpty,
      );
      fixture.expectIsolation();
    });
  });
}
