import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/modules/mood/mood_store.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';

import 'data_wipe_fixture.dart';

void registerMoodWriteFailureCase(bool committed,
    {bool failWithException = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'unconfirmed write blocks retries and permits wipe, committed=$committed, exception=$failWithException',
      () async {
    final fixture = await DataWipeFixture.create();
    await fixture.run(() async {
      const key = 'flutter.neura_mood_entries_v1';
      final entered = Completer<void>();
      final release = Completer<void>();
      var writeAttempts = 0;
      fixture.preferences.beforeSetValue = (candidate) async {
        if (candidate != key) return;
        writeAttempts++;
        if (!entered.isCompleted) entered.complete();
        await release.future;
        if (failWithException) throw StateError('Synthetic platform failure');
      };
      if (committed) {
        fixture.preferences.misreportedWrites.add(key);
      } else {
        fixture.preferences.refusedWrites.add(key);
      }
      final entry = MoodEntry(
          timestamp: DateTime.utc(2026, 11, 14),
          mood0to10: 4,
          note: 'Synthetic new note');
      final first = expectLater(MoodStore.instance.add(entry),
          throwsA(isA<MoodSaveUnconfirmedException>()));
      await entered.future;
      final queued = expectLater(MoodStore.instance.add(entry),
          throwsA(isA<MoodSaveUnconfirmedException>()));
      release.complete();
      await first;
      await queued;
      expect(writeAttempts, 1, reason: 'The queued write must be revoked too');
      expect(fixture.preferences.data.containsKey(key), committed);
      final before = Map<String, Object>.from(fixture.preferences.data);
      await expectLater(MoodStore.instance.getAll(),
          throwsA(isA<MoodSaveUnconfirmedException>()));
      await expectLater(MoodStore.instance.add(entry),
          throwsA(isA<MoodSaveUnconfirmedException>()));
      expect(fixture.preferences.data, before);
      await NeuraDataWipeService.wipeAllLocalData();
      expect(fixture.preferences.data, isEmpty);
      expect(await MoodStore.instance.getAll(), isEmpty);
      await expectLater(MoodStore.instance.add(entry), throwsStateError);
      fixture.expectIsolation();
    });
  });
}
