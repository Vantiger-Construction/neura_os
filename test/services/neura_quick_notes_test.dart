import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_language.dart';
import 'package:neuro_companion/services/neura_quick_notes.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var now = DateTime(2026, 11, 27, 9);
  late NeuraQuickNotes notes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.remove(NeuraQuickNotes.storageKey);
    now = DateTime(2026, 11, 27, 9);
    // A reversible stand-in for the device-key cipher, marked so the test
    // can check nothing is stored in the clear.
    notes = NeuraQuickNotes(
      encrypt: (json) async =>
          'sealed:${base64Encode(utf8.encode(jsonEncode(json)))}',
      decrypt: (blob) async => jsonDecode(
        utf8.decode(base64Decode(blob.substring('sealed:'.length))),
      ) as Map<String, dynamic>,
      now: () => now,
    );
    NeuraNoteSession.instance.discard();
  });

  test('notes are sealed, newest first, and keep their language', () async {
    await notes.add('comprar leche', languages: [NeuraLanguage.es]);
    now = now.add(const Duration(minutes: 5));
    await notes.add('call the clinic');
    final stored = NeuraPrefsCache.prefs.getString(NeuraQuickNotes.storageKey)!;
    expect(stored, startsWith('sealed:'));
    expect(stored, isNot(contains('leche')));

    final list = await notes.list();
    expect(list.map((note) => note.text), ['call the clinic', 'comprar leche']);
    expect(list.last.languages, [NeuraLanguage.es]);
    expect(list.first.kind, NeuraQuickNoteKind.note);
  });

  test('empty and oversized notes are refused; the oldest is dropped',
      () async {
    expect(() => notes.add('   '), throwsArgumentError);
    expect(
      () => notes.add('x' * (NeuraQuickNotes.maxNoteLength + 1)),
      throwsArgumentError,
    );
    for (var i = 0; i < NeuraQuickNotes.maxNotes + 2; i++) {
      await notes.add('note $i');
    }
    final list = await notes.list();
    expect(list, hasLength(NeuraQuickNotes.maxNotes));
    expect(list.last.text, 'note 2');
  });

  test('delete removes one note and notifies open screens', () async {
    final keep = await notes.add('keep');
    final drop = await notes.add('drop');
    final before = notes.revision.value;
    await notes.delete(drop.id);
    expect(notes.revision.value, greaterThan(before));
    expect((await notes.list()).map((note) => note.id), [keep.id]);
  });

  test('a transcript is bounded and refuses words once full', () {
    final transcript = NeuraNoteTranscript();
    expect(transcript.add('Hola a todos', language: NeuraLanguage.es), isTrue);
    expect(transcript.add('Ciao', language: NeuraLanguage.it), isTrue);
    expect(transcript.add('  '), isTrue);
    expect(transcript.count, 2);
    expect(transcript.text, 'Hola a todos\nCiao');
    expect(transcript.languages, [NeuraLanguage.es, NeuraLanguage.it]);
    final big = 'a' * NeuraQuickNotes.maxTranscriptLength;
    expect(transcript.add(big), isFalse);
    expect(transcript.count, 2, reason: 'nothing is dropped from the middle');
  });

  test('a note session writes only while active and saves one transcript',
      () async {
    final session = NeuraNoteSession.instance;
    expect(session.add('not yet'), isFalse);
    session.start(NeuraLanguage.de);
    expect(session.add('Guten Morgen', language: NeuraLanguage.de), isTrue);
    expect(session.add('Bonjour', language: NeuraLanguage.fr), isTrue);
    expect(session.phrases.value, 2);

    // Leaving chat pauses; the words stay until saved or discarded.
    session.pause();
    expect(session.add('while paused'), isFalse);
    expect(session.hasUnsaved, isTrue);

    final saved = await session.save(store: notes);
    expect(saved!.kind, NeuraQuickNoteKind.transcript);
    expect(saved.text, 'Guten Morgen\nBonjour');
    expect(saved.languages, [NeuraLanguage.de, NeuraLanguage.fr]);
    expect(session.hasUnsaved, isFalse);
    expect(session.phrases.value, 0);
    expect(session.language, NeuraLanguage.de);
  });

  test('a data wipe clears unsaved words', () {
    final session = NeuraNoteSession.instance;
    session.start(NeuraLanguage.en);
    session.add('private words');
    session.resetAfterDataWipe();
    expect(session.active.value, isFalse);
    expect(session.hasUnsaved, isFalse);
  });
}
