import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/modules/mood/mood_store.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../../helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wipe retains and drains an admitted legacy migration across retries',
      () async {
    final fixture = await DataWipeFixture.create();
    await fixture.run(() async {
      const key = 'neura_mood_entries_v1';
      await NeuraPrefsCache.prefs.setString(
          key,
          MoodEntry.encodeList([
            MoodEntry(
                timestamp: DateTime.utc(2026, 11, 14),
                mood0to10: 4,
                note: 'Synthetic legacy migration')
          ]));
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.preferences.beforeSetValue = (candidate) async {
        if (candidate != 'flutter.$key') return;
        entered.complete();
        await release.future;
      };
      final reading = MoodStore.instance.getAll();
      // Handle any error immediately, including on the pre-correction source.
      final observedRead = reading.then<Object>((value) => value,
          onError: (Object error) => error);
      try {
        await entered.future;
        for (var retry = 0; retry < 2; retry++) {
          await expectLater(
              NeuraDataWipeService.wipeAllLocalData(),
              throwsA(isA<NeuraDataWipeException>().having(
                  (error) => error.failedSteps,
                  'failed steps',
                  contains('mood history writer shutdown'))));
        }
      } finally {
        release.complete();
        await observedRead;
      }
      expect(await observedRead, isEmpty);
      await NeuraDataWipeService.wipeAllLocalData();
      expect(fixture.preferences.data, isEmpty);
      expect(fixture.secrets, {DataWipeFixture.tombstoneKey: 'disabled'});
      fixture.expectIsolation();
    });
  });
}
