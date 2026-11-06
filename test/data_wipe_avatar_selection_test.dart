import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/avatar_registry.dart';
import 'package:neuro_companion/services/avatar_service.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import 'helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('held avatar write makes wipe incomplete until a verified retry',
      () async {
    final f = await DataWipeFixture.create();
    final service = AvatarService.instance;
    service.resetForTesting();
    await f.run(() async {
      final started = Completer<void>();
      final release = Completer<void>();
      f.preferences.beforeSetValue = (key) async {
        if (!key.endsWith('avatar_selected_id')) return;
        started.complete();
        await release.future;
      };
      final saving = service.selectAvatar(AvatarRegistry.expressiveFaceId);
      try {
        await started.future;
        final wipe = NeuraDataWipeService.wipeAllLocalData();
        expect(await AvatarService().selectAvatar('neuro'), isFalse,
            reason: 'Every production caller shares the suspended writer');
        await expectLater(
          wipe,
          throwsA(isA<NeuraDataWipeException>().having(
            (e) => e.failedSteps,
            'failed steps',
            contains('preferences deletion'),
          )),
        );
        expect(f.preferences.clearCalls, 0,
            reason: 'Never clear underneath an uncancellable native write');
        release.complete();
        expect(await saving, isFalse);
        expect(f.preferences.data.values,
            contains(AvatarRegistry.expressiveFaceId));
        expect((await service.getSelectedAvatar()).id, 'neura');
        await NeuraDataWipeService.wipeAllLocalData();
        expect(f.preferences.clearCalls, 1);
        expect(f.preferences.data, isEmpty);
        expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
        final restarted = AvatarService.forTesting();
        expect((await restarted.getSelectedAvatar()).id, 'neura');
      } finally {
        if (!release.isCompleted) release.complete();
        await saving;
        service.resetForTesting();
      }
    });
  });
}
