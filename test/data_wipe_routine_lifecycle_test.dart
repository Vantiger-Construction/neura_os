import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/dashboard/proactive_banner_service.dart';
import 'package:neuro_companion/intelligence/neura_intelligence_controller.dart';
import 'package:neuro_companion/intelligence/routine_model.dart';
import 'package:neuro_companion/modules/human/human_prefs_controller.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import 'helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a timed-out routine writer prevents preference clear until retry',
    () async {
      final fixture = await DataWipeFixture.create();
      const key = 'neura.initiative.routine.v1';
      final started = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      await fixture.run(() async {
        SafeBoot.instance.safeMode.value = false;
        NeuraIntelligenceController.instance.resetForTesting();
        HumanPrefsController.instance.resetAfterDataWipe();
        await NeuraPrefsCache.prefs.setString(
          key,
          jsonEncode(
            NeuraRoutineModel.empty()
                .recordOpen(DateTime.now().subtract(const Duration(days: 5)))
                .toJson(),
          ),
        );
        fixture.preferences.beforeSetValue = (storedKey) async {
          if (storedKey.endsWith(key)) {
            if (!started.isCompleted) started.complete();
            await release.future;
          }
        };
        final service = ProactiveBannerService.instance;
        final evaluation = service.maybeGetBannerOnAppOpen();
        await started.future;
        try {
          await expectLater(
            NeuraDataWipeService.wipeAllLocalData(),
            throwsA(
              isA<NeuraDataWipeException>().having(
                (error) => error.failedSteps,
                'failures',
                contains('proactive banner cache reset'),
              ),
            ),
          );
          expect(fixture.preferences.clearCalls, 0);
          expect(SafeBoot.instance.safeMode.value, isTrue);
          expect(service.resumeAfterDataWipe, throwsStateError);
        } finally {
          release.complete();
          await evaluation;
        }
        fixture.preferences.beforeSetValue = null;
        await NeuraDataWipeService.wipeAllLocalData();
        expect(fixture.preferences.data, isEmpty);
        expect(await service.maybeGetBannerOnAppOpen(), isNull);
        // A fresh post-wipe write must not be removed by detached old cleanup.
        SafeBoot.instance.safeMode.value = false;
        await service.maybeGetBannerOnAppOpen();
        await service.resetAfterDataWipe();
        expect(
          fixture.preferences.data.keys.any((k) => k.endsWith(key)),
          isTrue,
        );
        fixture.expectIsolation();
      });
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
