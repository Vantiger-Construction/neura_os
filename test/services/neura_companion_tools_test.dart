import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/models/journal_entry.dart';
import 'package:neuro_companion/modules/chat/neura_bedtime_story_screen.dart';
import 'package:neuro_companion/modules/chat/neura_focus_together_screen.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/mood/screens/neura_mood_gallery_screen.dart';
import 'package:neuro_companion/mood/services/neura_mood_weather.dart';
import 'package:neuro_companion/mood/widgets/neura_mood_painting.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/services/emotion_analysis_service.dart';
import 'package:neuro_companion/services/neura_future_notes.dart';
import 'package:neuro_companion/services/neura_on_this_day.dart';
import 'package:neuro_companion/services/neura_tone_check.dart';
import 'package:neuro_companion/services/neura_worry_parking.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> _seal(Map<String, dynamic> json) async =>
    'sealed:${base64Encode(utf8.encode(jsonEncode(json)))}';
Future<Map<String, dynamic>> _open(String blob) async =>
    jsonDecode(utf8.decode(base64Decode(blob.substring('sealed:'.length))))
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.clear();
  });

  group('worry parking', () {
    var now = DateTime(2026, 11, 20, 9);
    late NeuraWorryParking parking;
    setUp(() {
      now = DateTime(2026, 11, 20, 9);
      parking =
          NeuraWorryParking(encrypt: _seal, decrypt: _open, now: () => now);
    });

    test('recognizes park commands only', () {
      expect(NeuraWorryParking.worryFrom('Park it: the rent'), 'the rent');
      expect(
        NeuraWorryParking.worryFrom('park this worry - the exam'),
        'the exam',
      );
      expect(NeuraWorryParking.worryFrom('park it:'), isNull);
      expect(NeuraWorryParking.worryFrom('Where can I park it?'), isNull);
    });

    test('worries come back at worry time and can be sorted', () async {
      final rent = await parking.park('The rent is due');
      await parking.park('Exam on Friday');
      final stored =
          NeuraPrefsCache.prefs.getString(NeuraWorryParking.storageKey)!;
      expect(stored, isNot(contains('rent')));

      expect(await parking.due(), isEmpty); // 9 a.m.: not worry time yet.
      now = DateTime(2026, 11, 20, 18, 5);
      expect((await parking.due()).length, 2);
      expect(await parking.offerCount(), 2);
      expect(await parking.offerCount(), 0); // Once a day.

      await parking.addStep(rent.id, 'Call the landlord');
      await parking.letGo((await parking.list())[1].id);
      expect((await parking.list()).single.step, 'Call the landlord');

      await parking.keepForLater(rent.id);
      expect(await parking.due(), isEmpty);
      now = DateTime(2026, 11, 21, 18, 1);
      expect((await parking.due()).single.text, 'The rent is due');
    });
  });

  test('tone check notices blame, insults, shouting and heat', () {
    final notes = NeuraToneCheck.observe(
      'You NEVER listen and this is RIDICULOUS!!! Thanks a lot.',
    );
    expect(notes.any((n) => n.contains('blame')), isTrue);
    expect(notes.any((n) => n.contains('insults')), isTrue);
    expect(notes.any((n) => n.contains('shouting')), isTrue);
    expect(notes.any((n) => n.contains('exclamation')), isTrue);
    expect(notes.any((n) => n.contains('sarcastic')), isTrue);
    expect(
      NeuraToneCheck.observe('Could we talk about chores this weekend?'),
      isEmpty,
    );
    expect(
      NeuraToneCheck.rewriteRequest('Hi', to: 'my boss'),
      'My message to my boss:\nHi',
    );
  });

  group('on this day', () {
    final now = DateTime(2026, 11, 20, 10);
    final yearAgo = DateTime(2025, 11, 20, 19);
    JournalEntry j(String text, DateTime at) =>
        JournalEntry(id: '$at', timestamp: at, content: text);

    test('a good day comes back; a hard day never does', () {
      expect(
        NeuraOnThisDay.memoryOf(
          DateTime(2025, 11, 20),
          [MoodEntry(timestamp: yearAgo, mood0to10: 8, note: '')],
          [j('Picnic by the lake with my sister.', yearAgo)],
        ),
        'Picnic by the lake with my sister.',
      );
      expect(
        NeuraOnThisDay.memoryOf(
          DateTime(2025, 11, 20),
          [MoodEntry(timestamp: yearAgo, mood0to10: 3, note: '')],
          [j('Picnic by the lake.', yearAgo)],
        ),
        isNull,
      );
      expect(
        NeuraOnThisDay.memoryOf(
          DateTime(2025, 11, 20),
          const [],
          [j('I felt so alone and sad all day.', yearAgo)],
        ),
        isNull,
      );
    });

    test('off by default, then once a day', () async {
      final day = NeuraOnThisDay(
        moods: () async => const [],
        journal: () async => [j('Started learning guitar!', yearAgo)],
        now: () => now,
      );
      expect(await day.offer(), isNull);
      await day.setEnabled(true);
      final memory = await day.offer();
      expect(memory?.when, 'A year ago today');
      expect(memory?.text, 'Started learning guitar!');
      expect(await day.offer(), isNull);
    });
  });

  test('bright spots are kept apart from notes and come second', () async {
    var now = DateTime(2026, 11, 1);
    final notes =
        NeuraFutureNotes(encrypt: _seal, decrypt: _open, now: () => now);
    await notes.add('Got the job!', kind: FutureNoteKind.brightSpot);
    await notes.add('You can do hard things.');
    expect(await notes.brightSpotsOn(DateTime(2026, 11, 1)), ['Got the job!']);
    now = now.add(const Duration(days: 2));
    final first = await notes.offerFor(
      const EmotionRead(primary: 'sadness', intensity: 0.8),
    );
    expect(first?.kind, FutureNoteKind.note);
  });

  test('rain weather swaps the room sound for rain', () {
    expect(
      NeuraShellState.ambientAssetFor(
          NeuraRoom.penthouse, NeuraMoodWeather.rain),
      NeuraShellState.rainSoundAsset,
    );
    expect(
      NeuraShellState.ambientAssetFor(
          NeuraRoom.penthouse, NeuraMoodWeather.clear),
      NeuraRoom.penthouse.ambientSoundAsset,
    );
  });

  test('bedtime stories are read in short chunks', () {
    final long = List.filled(40, 'The waves rolled in softly.').join(' ');
    final chunks = NeuraBedtimeStoryScreen.chunks('Once upon a time.\n\n$long');
    expect(chunks.first, 'Once upon a time.');
    expect(chunks.length, greaterThan(2));
    expect(chunks.every((c) => c.length <= 600), isTrue);
    expect(
      NeuraBedtimeStoryScreen.request('a calm sea', ' an old dog '),
      'Please tell me a bedtime story set in a calm sea. Include: an old dog.',
    );
  });

  testWidgets('focus together counts down, checks in at halfway, finishes', (
    tester,
  ) async {
    final said = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: NeuraFocusTogetherScreen(speak: (text) async => said.add(text)),
    ));
    await tester.tap(find.text('15 min'));
    await tester.tap(find.byKey(const Key('focus-start')));
    await tester.pump();
    expect(find.text('15:00'), findsOneWidget);
    await tester.pump(const Duration(minutes: 7, seconds: 30));
    expect(said.last, contains('Halfway'));
    await tester.pump(const Duration(minutes: 7, seconds: 31));
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);
    expect(
      NeuraPrefsCache.prefs.getInt(NeuraFocusTogetherScreen.sessionsKey),
      1,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the gallery paints one picture per week with check-ins', (
    tester,
  ) async {
    final monday = DateTime(2026, 11, 16, 9);
    final entries = [
      MoodEntry(timestamp: monday, mood0to10: 8, note: '', energy0to10: 7),
      MoodEntry(
        timestamp: monday.add(const Duration(days: 2)),
        mood0to10: 4,
        note: '',
        sleepHours: 5,
      ),
      MoodEntry(
        timestamp: monday.subtract(const Duration(days: 7)),
        mood0to10: 6,
        note: '',
      ),
    ];
    expect(NeuraMoodGalleryScreen.weeksWithEntries(entries), [
      DateTime(2026, 11, 16),
      DateTime(2026, 11, 9),
    ]);
    final painting = NeuraMoodPainting(
      weekStart: DateTime(2026, 11, 16),
      entries: entries,
    );
    expect(painting.entries, hasLength(2));
    await tester.pumpWidget(MaterialApp(
      home: NeuraMoodGalleryScreen(loadEntries: () async => entries),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Week of'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
