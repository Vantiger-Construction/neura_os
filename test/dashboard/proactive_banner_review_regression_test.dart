import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/dashboard/proactive_banner_service.dart';
import 'package:neuro_companion/intelligence/intelligence_preferences.dart';
import 'package:neuro_companion/intelligence/neura_intelligence_controller.dart';
import 'package:neuro_companion/intelligence/routine_model.dart';
import 'package:neuro_companion/modules/human/human_prefs.dart';
import 'package:neuro_companion/modules/human/human_prefs_controller.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
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
    now = DateTime.utc(2026, 10, 29, 10);
    controller.resetForTesting();
    HumanPrefsController.instance.prefs.value = HumanPrefs.defaults;
    SafeBoot.instance.safeMode.value = false;
    // These tests exercise routine delivery, not the independent focus radar.
    // Its singleton otherwise timestamps itself with the real wall clock;
    // advancing our fake clock can accidentally make that signal fresh on CI.
    FocusController.instance.state.value = FocusState(
      mode: FocusMode.off,
      startedAt: now.subtract(const Duration(days: 60)),
    );
    service = ProactiveBannerService.forTesting(clock: () => now);
    addTearDown(service.disposeForTesting);
    await NeuraPrefsCache.prefs.setString(
      routineKey,
      jsonEncode(
        NeuraRoutineModel.empty()
            .recordOpen(now.subtract(const Duration(days: 5)))
            .toJson(),
      ),
    );
  });

  test('a stalled routine write does not block a welcome-back card', () async {
    await fixture.run(() async {
      final started = Completer<void>();
      final release = Completer<void>();
      fixture.preferences.beforeSetValue = (key) async {
        if (key.endsWith(routineKey)) {
          if (!started.isCompleted) started.complete();
          await release.future;
        }
      };
      final request = service.maybeGetBannerOnAppOpen();
      await started.future;
      try {
        final banner = await request.timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        );
        expect(banner?.kind, ProactiveBannerKind.presence);
      } finally {
        release.complete();
        await request;
      }
    });
  });

  test(
    'learning disabled prevents reading routine history into candidates',
    () async {
      await fixture.run(() async {
        HumanPrefsController.instance.prefs.value =
            HumanPrefs.defaults.copyWith(allowLearning: false);
        final banner = await service.maybeGetBannerOnAppOpen();
        expect(banner, isNull);
        expect(
          controller.records.where(
            (record) => record.receipt.specialistId.startsWith('initiative.'),
          ),
          isEmpty,
        );
        fixture.expectIsolation();
      });
    },
  );

  test('quiet hours preserve welcome-back until display is allowed', () async {
    await fixture.run(() async {
      await controller.updatePreferences(
        const NeuraIntelligencePreferences(
          quietHoursEnabled: true,
          quietHoursStart: 0,
          quietHoursEnd: 0,
        ),
      );
      expect(await service.maybeGetBannerOnAppOpen(), isNull);
      now = now.add(const Duration(hours: 2));
      await controller.updatePreferences(const NeuraIntelligencePreferences());
      final banner = await service.maybeGetBannerOnAppOpen();
      expect(banner?.kind, ProactiveBannerKind.presence);
      fixture.expectIsolation();
    });
  });

  test('concurrent evaluations offer at most one initiative card', () async {
    await fixture.run(() async {
      final started = Completer<void>();
      final release = Completer<void>();
      fixture.preferences.beforeSetValue = (key) async {
        if (key.endsWith(routineKey)) {
          if (!started.isCompleted) started.complete();
          await release.future;
        }
      };
      await controller.initialize();
      final first = service.maybeGetBannerOnAppOpen();
      final second = service.maybeGetBannerOnAppOpen();
      await started.future;
      release.complete();
      final banners = await Future.wait([first, second]);
      expect(banners.whereType<ProactiveBanner>(), hasLength(1));
      fixture.expectIsolation();
    });
  });

  test(
    'turning learning off then on starts a fresh routine baseline',
    () async {
      await fixture.run(() async {
        HumanPrefsController.instance.prefs.value =
            HumanPrefs.defaults.copyWith(allowLearning: false);
        expect(await service.maybeGetBannerOnAppOpen(), isNull);
        HumanPrefsController.instance.prefs.value = HumanPrefs.defaults;
        expect(await service.maybeGetBannerOnAppOpen(), isNull);
        expect(
          controller.records.where(
            (record) => record.receipt.specialistId.startsWith('initiative.'),
          ),
          isEmpty,
        );
        fixture.expectIsolation();
      });
    },
  );

  test(
    'turning proactivity off then on cannot resurrect a stale welcome',
    () async {
      await fixture.run(() async {
        await controller.updatePreferences(
          const NeuraIntelligencePreferences(
            enabled: false,
            proactivityLevel: NeuraProactivityLevel.off,
          ),
        );
        expect(await service.maybeGetBannerOnAppOpen(), isNull);
        await controller.updatePreferences(
          const NeuraIntelligencePreferences(),
        );
        expect(await service.maybeGetBannerOnAppOpen(), isNull);
        fixture.expectIsolation();
      });
    },
  );

  test('cooldown preserves welcome-back eligibility', () async {
    await fixture.run(() async {
      await NeuraPrefsCache.prefs.setString(
        'neura.proactive_banner.state.v2',
        jsonEncode({'lastShownEpochMs': now.millisecondsSinceEpoch}),
      );
      expect(await service.maybeGetBannerOnAppOpen(), isNull);
      now = now.add(const Duration(hours: 13));
      final banner = await service.maybeGetBannerOnAppOpen();
      expect(banner?.kind, ProactiveBannerKind.presence);
      fixture.expectIsolation();
    });
  });

  test(
    'unshown welcome is retried, and a shown welcome is consumed once',
    () async {
      await fixture.run(() async {
        final first = await service.maybeGetBannerOnAppOpen();
        expect(first?.kind, ProactiveBannerKind.presence);
        expect(await service.maybeGetBannerOnAppOpen(), isNull);
        service.releaseUnshown(first!);
        final retried = await service.maybeGetBannerOnAppOpen();
        expect(retried?.candidate.id, first.candidate.id);
        await service.recordShown(retried!);
        await service.recordShown(retried);
        now = now.add(const Duration(hours: 13));
        expect(await service.maybeGetBannerOnAppOpen(), isNull);
        fixture.expectIsolation();
      });
    },
  );

  test('revocation and Safe Mode invalidate already-offered cards', () async {
    await fixture.run(() async {
      final banner = await service.maybeGetBannerOnAppOpen();
      expect(banner, isNotNull);
      SafeBoot.instance.safeMode.value = true;
      expect(service.canDisplay(banner!), isFalse);
      expect(await service.maybeGetBannerOnAppOpen(), isNull);
      SafeBoot.instance.safeMode.value = false;
      HumanPrefsController.instance.prefs.value = HumanPrefs.defaults.copyWith(
        allowLearning: false,
      );
      expect(service.canDisplay(banner), isFalse);
      await service.recordShown(banner);
      await service.recordOutcome(banner: banner, acted: true);
      expect(
        controller.records.where(
          (record) => record.receipt.userOutcome.name == 'acted',
        ),
        isEmpty,
      );
      fixture.expectIsolation();
    });
  });

  test('saved learning refusal is honored after settings initialize', () async {
    await fixture.run(() async {
      await NeuraPrefsCache.prefs.setString('neura.human.prefs.v1',
          HumanPrefs.defaults.copyWith(allowLearning: false).toJsonString());
      await HumanPrefsController.instance.init();
      expect(await service.maybeGetBannerOnAppOpen(), isNull);
      expect(
          controller.records.where((record) =>
              record.receipt.specialistId.startsWith('initiative.')),
          isEmpty);
      fixture.expectIsolation();
    });
  });

  test('private-room suppression preserves the pending greeting', () async {
    await fixture.run(() async {
      await NeuraPrefsCache.prefs
          .setString(NeuraRoom.currentRoomPrefsKey, 'reflection_bay');
      expect(await service.maybeGetBannerOnAppOpen(), isNull);
      await NeuraPrefsCache.prefs
          .setString(NeuraRoom.currentRoomPrefsKey, 'welcome_atrium');
      expect((await service.maybeGetBannerOnAppOpen())?.kind,
          ProactiveBannerKind.presence);
      fixture.expectIsolation();
    });
  });

  test(
    'a pre-wipe receipt cannot write into the post-wipe generation',
    () async {
      await fixture.run(() async {
        final banner = await service.maybeGetBannerOnAppOpen();
        expect(banner, isNotNull);
        await service.resetAfterDataWipe();
        await NeuraPrefsCache.prefs.clear();
        service.resumeAfterDataWipe();
        await service.recordShown(banner!);
        await service.recordOutcome(banner: banner, acted: true);
        expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
        fixture.expectIsolation();
      });
    },
  );
}
