import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/modules/mood/mood_store.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../../helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'neura_mood_entries_v1';
  const platformKey = 'flutter.neura_mood_entries_v1';
  MoodEntry entry(String note) => MoodEntry(
      timestamp: DateTime.utc(2026, 11, 14), mood0to10: 4, note: note);

  test('a damaged encrypted history cannot become empty or be overwritten',
      () async {
    final fixture = await DataWipeFixture.create();
    await fixture.run(() async {
      final crypto = await MemoryCrypto.demo();
      final envelope = jsonDecode(await crypto.encryptJson({
        'items': [entry('Synthetic original').toJson()]
      })) as Map<String, dynamic>;
      final mac = base64Decode(envelope['m'] as String);
      mac[0] ^= 1;
      envelope['m'] = base64Encode(mac);
      final corrupt = jsonEncode(envelope);
      await NeuraPrefsCache.prefs.setString(key, corrupt);
      await expectLater(MoodStore.instance.getAll(), throwsA(anything));
      await expectLater(MoodStore.instance.add(entry('Synthetic replacement')),
          throwsA(anything));
      expect(fixture.preferences.data[platformKey], corrupt);
      expect(NeuraPrefsCache.prefs.getString(key), corrupt);
      fixture.expectIsolation();
    });
  });

  test('legacy rows migrate and new optional metadata survives encryption',
      () async {
    final fixture = await DataWipeFixture.create();
    await fixture.run(() async {
      await NeuraPrefsCache.prefs
          .setString(key, jsonEncode([entry('Synthetic legacy').toJson()]));
      expect(
          (await MoodStore.instance.getAll()).single.note, 'Synthetic legacy');
      await MoodStore.instance.add(MoodEntry(
          timestamp: DateTime.utc(2026, 11, 14, 1),
          mood0to10: 7,
          note: 'Synthetic optional values',
          energy0to10: 0,
          sleepHours: 0));
      await NeuraPrefsCache.prefs.reload();
      final reopened = await MoodStore.instance.getAll();
      expect(reopened.first.energy0to10, isNull);
      expect(reopened.first.sleepHours, isNull);
      expect(reopened.last.energy0to10, 0);
      expect(reopened.last.sleepHours, 0);
      final raw = fixture.preferences.data[platformKey] as String;
      expect(raw, isNot(contains('Synthetic')));
      expect(raw, isNot(contains('sleepHours')));
      fixture.expectIsolation();
    });
  });

  test('invalid authenticated rows cannot be silently dropped', () async {
    final fixture = await DataWipeFixture.create();
    await fixture.run(() async {
      final raw = await (await MemoryCrypto.demo()).encryptJson({
        'items': ['invalid synthetic row']
      });
      await NeuraPrefsCache.prefs.setString(key, raw);
      await expectLater(MoodStore.instance.getAll(), throwsA(anything));
      await expectLater(MoodStore.instance.add(entry('Synthetic new note')),
          throwsA(anything));
      expect(fixture.preferences.data[platformKey], raw);
      fixture.expectIsolation();
    });
  });
}
