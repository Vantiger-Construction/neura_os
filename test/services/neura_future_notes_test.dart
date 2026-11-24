import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/emotion_analysis_service.dart';
import 'package:neuro_companion/services/neura_future_notes.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var now = DateTime(2026, 11, 1, 9);
  late NeuraFutureNotes notes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    // The cache keeps one instance across tests; start each one empty.
    await NeuraPrefsCache.prefs.remove(NeuraFutureNotes.storageKey);
    now = DateTime(2026, 11, 1, 9);
    // A reversible stand-in for the device-key cipher, marked so the test
    // can check nothing is stored in the clear.
    notes = NeuraFutureNotes(
      encrypt: (json) async =>
          'sealed:${base64Encode(utf8.encode(jsonEncode(json)))}',
      decrypt: (blob) async => jsonDecode(
        utf8.decode(base64Decode(blob.substring('sealed:'.length))),
      ) as Map<String, dynamic>,
      now: () => now,
    );
  });

  test('note commands are recognized; ordinary messages are not', () {
    expect(
      NeuraFutureNotes.noteFrom('Note to future me: you got through March.'),
      'you got through March.',
    );
    expect(
      NeuraFutureNotes.noteFrom('note for my future self - call Sam'),
      'call Sam',
    );
    expect(NeuraFutureNotes.noteFrom('Note to future me:'), isNull);
    expect(NeuraFutureNotes.noteFrom('I wrote a note to future me'), isNull);
    expect(NeuraFutureNotes.noteFrom('How are you?'), isNull);
  });

  test('notes are stored sealed and offered back only in hard moments',
      () async {
    await notes.add('You have survived every bad day so far.');
    final stored = NeuraPrefsCache.prefs.getString(
      NeuraFutureNotes.storageKey,
    )!;
    expect(stored, startsWith('sealed:'));
    expect(stored, isNot(contains('survived')));

    const sad = EmotionRead(primary: 'sadness', intensity: 0.8);
    // Too fresh: a note is not handed straight back.
    expect(await notes.offerFor(sad), isNull);

    now = now.add(const Duration(days: 2));
    expect(
      await notes.offerFor(const EmotionRead(primary: 'joy', intensity: 1)),
      isNull,
    );
    expect(
      await notes
          .offerFor(const EmotionRead(primary: 'sadness', intensity: 0.2)),
      isNull,
    );
    final offered = await notes.offerFor(sad);
    expect(offered?.text, 'You have survived every bad day so far.');

    // One offer per cooldown, then the note can return.
    now = now.add(const Duration(days: 1));
    expect(await notes.offerFor(sad), isNull);
    now = now.add(NeuraFutureNotes.offerCooldown);
    expect(await notes.offerFor(sad), isNotNull);
  });

  test('the least recently offered note comes back first', () async {
    await notes.add('First');
    now = now.add(const Duration(minutes: 1));
    await notes.add('Second');
    now = now.add(const Duration(days: 2));
    const low = EmotionRead(masked: true);
    expect((await notes.offerFor(low))!.text, 'First');
    now = now.add(NeuraFutureNotes.offerCooldown);
    expect((await notes.offerFor(low))!.text, 'Second');
  });

  test('notes are bounded and can be deleted', () async {
    for (var i = 0; i < NeuraFutureNotes.maxNotes + 3; i++) {
      await notes.add('Note $i');
    }
    final all = await notes.list();
    expect(all, hasLength(NeuraFutureNotes.maxNotes));
    expect(all.first.text, 'Note 3');
    await notes.delete(all.first.id);
    expect(await notes.list(), hasLength(NeuraFutureNotes.maxNotes - 1));
    expect(
      () => notes.add('x' * (NeuraFutureNotes.maxNoteLength + 1)),
      throwsArgumentError,
    );
    expect(() => notes.add('   '), throwsArgumentError);
  });
}
