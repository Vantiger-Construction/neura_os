import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/models/journal_entry.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/services/neura_morning_reflection.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final yesterday = DateTime(2026, 11, 19, 18);
  var now = DateTime(2026, 11, 20, 8);
  var moods = <MoodEntry>[];
  var journal = <JournalEntry>[];
  late NeuraMorningReflection reflection;

  JournalEntry entry(String text, DateTime at) => JournalEntry(
      id: 'j-${at.millisecondsSinceEpoch}', timestamp: at, content: text);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.remove(NeuraMorningReflection.storageKey);
    await NeuraPrefsCache.prefs.remove(NeuraMorningReflection.enabledKey);
    now = DateTime(2026, 11, 20, 8);
    moods = [
      MoodEntry(timestamp: yesterday, mood0to10: 6, note: 'Walked with Sam'),
      MoodEntry(
        timestamp: yesterday.subtract(const Duration(days: 3)),
        mood0to10: 2,
        note: 'Older day',
      ),
    ];
    journal = [entry('Finished the garden bed.', yesterday)];
    reflection = NeuraMorningReflection(
      encrypt: (json) async =>
          'sealed:${base64Encode(utf8.encode(jsonEncode(json)))}',
      decrypt: (blob) async => jsonDecode(
        utf8.decode(base64Decode(blob.substring('sealed:'.length))),
      ) as Map<String, dynamic>,
      moods: () async => moods,
      journal: () async => journal,
      now: () => now,
    );
  });

  test('the prompt holds only yesterday, and nothing after crisis words', () {
    final prompt = NeuraMorningReflection.promptFor(
      NeuraMorningReflection.yesterdayOf(now),
      moods,
      journal,
    )!;
    expect(prompt, contains('mood 6/10'));
    expect(prompt, contains('Walked with Sam'));
    expect(prompt, contains('Finished the garden bed.'));
    expect(prompt, isNot(contains('Older day')));

    expect(
      NeuraMorningReflection.promptFor(
        NeuraMorningReflection.yesterdayOf(now),
        moods,
        [entry('I want to kill myself', yesterday)],
      ),
      isNull,
    );
    expect(
      NeuraMorningReflection.promptFor(DateTime(2026, 1, 1), moods, journal),
      isNull,
    );
  });

  test('off by default: nothing is written or shown', () async {
    var calls = 0;
    expect(
        await reflection.prepareIfDue((_, __) async => '${calls++}'), isNull);
    expect(calls, 0);
    expect(await reflection.todayNote(), isNull);
  });

  test('once a day, stored sealed, dismissible', () async {
    await reflection.setEnabled(true);
    var calls = 0;
    Future<String?> write(String system, String prompt) async {
      calls++;
      expect(system, contains('Do not invent anything'));
      expect(prompt, contains('garden bed'));
      return 'You found time for the garden. That walk with Sam sounded good.';
    }

    final note = await reflection.prepareIfDue(write);
    expect(note, contains('garden'));
    final stored =
        NeuraPrefsCache.prefs.getString(NeuraMorningReflection.storageKey)!;
    expect(stored, startsWith('sealed:'));
    expect(stored, isNot(contains('garden')));

    expect(await reflection.prepareIfDue(write), note);
    expect(calls, 1);
    expect(await reflection.todayNote(), note);
    await reflection.dismiss();
    expect(await reflection.todayNote(), isNull);

    // The next day writes a new one.
    now = now.add(const Duration(days: 1));
    journal = [
      entry('Quiet day of reading.', now.subtract(const Duration(days: 1)))
    ];
    moods = [];
    await reflection.prepareIfDue(write).catchError((_) => null);
    expect(calls, 2);
  });

  test('a failed or blocked write is not retried the same day', () async {
    await reflection.setEnabled(true);
    var calls = 0;
    expect(
      await reflection.prepareIfDue((_, __) async {
        calls++;
        return null;
      }),
      isNull,
    );
    expect(
      await reflection.prepareIfDue((_, __) async {
        calls++;
        return 'late';
      }),
      isNull,
    );
    expect(calls, 1);
  });

  test('before the day starts, nothing runs', () async {
    await reflection.setEnabled(true);
    now = DateTime(2026, 11, 20, 2);
    var calls = 0;
    await reflection.prepareIfDue((_, __) async => '${calls++}');
    expect(calls, 0);
  });

  test('turning it off deletes the note', () async {
    await reflection.setEnabled(true);
    await reflection.prepareIfDue((_, __) async => 'A kind note.');
    await reflection.setEnabled(false);
    expect(
      NeuraPrefsCache.prefs.getString(NeuraMorningReflection.storageKey),
      isNull,
    );
  });
}
