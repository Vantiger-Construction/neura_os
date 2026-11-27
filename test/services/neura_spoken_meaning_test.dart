import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_spoken_lexicon_store.dart';
import 'package:neuro_companion/services/neura_spoken_meaning.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NeuraSpokenText.normalize', () {
    test('turns streaming-model capitals into sentence case', () {
      expect(
        NeuraSpokenText.normalize("  HEY NEURA   I THINK I'M TIRED  "),
        "Hey neura I think I'm tired",
      );
    });

    test('leaves already punctuated mixed-case text alone', () {
      expect(
        NeuraSpokenText.normalize('Open Camera Hawk, please.'),
        'Open Camera Hawk, please.',
      );
    });

    test('empty and whitespace-only input stay empty', () {
      expect(NeuraSpokenText.normalize(''), '');
      expect(NeuraSpokenText.normalize('   '), '');
    });
  });

  group('NeuraSpokenLexicon', () {
    test('applies whole-word, case-insensitive corrections', () {
      final lexicon = NeuraSpokenLexicon([
        NeuraSpokenCorrection(heard: 'camera hock', meant: 'Camera Hawk'),
        NeuraSpokenCorrection(heard: 'neuro', meant: 'Neura'),
      ]);
      expect(
        lexicon.apply('Neuro, is Camera hock still recording?'),
        'Neura, is Camera Hawk still recording?',
      );
      // Not inside another word.
      expect(lexicon.apply('neurology'), 'neurology');
    });

    test('longer phrases win over shorter overlapping ones', () {
      final lexicon = NeuraSpokenLexicon([
        NeuraSpokenCorrection(heard: 'hock', meant: 'hawk'),
        NeuraSpokenCorrection(heard: 'camera hock', meant: 'Camera Hawk'),
      ]);
      expect(lexicon.apply('check camera hock'), 'check Camera Hawk');
    });

    test('newest entry replaces the old one and the list stays bounded', () {
      final lexicon = NeuraSpokenLexicon();
      for (var i = 0; i < NeuraSpokenLexicon.maxEntries + 5; i++) {
        lexicon.add(NeuraSpokenCorrection(heard: 'w$i', meant: 'm$i'));
      }
      expect(lexicon.entries.length, NeuraSpokenLexicon.maxEntries);
      expect(lexicon.entries.first.heard, 'w5');
      lexicon.add(NeuraSpokenCorrection(heard: 'W10', meant: 'other'));
      expect(
        lexicon.entries.where((e) => e.heard.toLowerCase() == 'w10').length,
        1,
      );
      expect(lexicon.entries.last.meant, 'other');
    });

    test('round-trips through JSON and ignores malformed entries', () {
      final lexicon = NeuraSpokenLexicon([
        NeuraSpokenCorrection(heard: 'pent house', meant: 'penthouse'),
      ]);
      final decoded = NeuraSpokenLexicon.decode(lexicon.encode());
      expect(decoded.apply('the pent house'), 'the penthouse');

      final messy = jsonEncode([
        {'heard': 'ok', 'meant': 'fine'},
        {'heard': '', 'meant': 'x'},
        {'heard': 'same', 'meant': 'SAME'},
        'not a map',
        {'heard': 'a b c d e', 'meant': 'too long'},
      ]);
      expect(NeuraSpokenLexicon.decode(messy).entries.length, 1);
      expect(NeuraSpokenLexicon.decode('not json').isEmpty, isTrue);
      expect(NeuraSpokenLexicon.decode(null).isEmpty, isTrue);
    });

    test('rejects control characters and oversized phrases', () {
      expect(
        () => NeuraSpokenCorrection(heard: 'a\u0000b', meant: 'c'),
        throwsFormatException,
      );
      expect(
        () => NeuraSpokenCorrection(heard: 'x' * 65, meant: 'c'),
        throwsFormatException,
      );
    });
  });

  group('NeuraSpokenLexicon.proposeFrom', () {
    test('finds the one short span the person fixed', () {
      final proposal = NeuraSpokenLexicon.proposeFrom(
        heard: 'Is camera hock still recording',
        sent: 'Is Camera Hawk still recording?',
      );
      expect(proposal?.heard, 'camera hock');
      expect(proposal?.meant, 'Camera Hawk');
    });

    test('ignores rewrites, pure additions and pure deletions', () {
      expect(
        NeuraSpokenLexicon.proposeFrom(
          heard: 'what is the weather',
          sent: 'never mind, play some music instead',
        ),
        isNull,
      );
      expect(
        NeuraSpokenLexicon.proposeFrom(
          heard: 'turn on the lights',
          sent: 'turn on the lights please',
        ),
        isNull,
      );
      expect(
        NeuraSpokenLexicon.proposeFrom(
          heard: 'turn on the lights now',
          sent: 'turn on the lights',
        ),
        isNull,
      );
      expect(
        NeuraSpokenLexicon.proposeFrom(heard: 'same text', sent: 'Same text.'),
        isNull,
      );
    });
  });

  group('NeuraSpokenTurnCue', () {
    test('explains that the message was spoken and asks to clarify', () {
      final cue = NeuraSpokenTurnCue.build();
      expect(cue, contains('aloud'));
      expect(cue, contains('one short question'));
      expect(utf8.encode(cue).length, lessThanOrEqualTo(512));
    });

    test('keeps the other cue whole or drops it, within the byte limit', () {
      final withEmotion = NeuraSpokenTurnCue.build(
        otherCue: 'They sound tired.',
      );
      expect(withEmotion, endsWith('They sound tired.'));

      final tooLong = NeuraSpokenTurnCue.build(otherCue: 'x' * 400);
      expect(tooLong, isNot(contains('xxx')));
      expect(utf8.encode(tooLong).length, lessThanOrEqualTo(512));

      expect(NeuraSpokenTurnCue.build(maxBytes: 10), isEmpty);
    });
  });

  group('NeuraSpokenLexiconStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await NeuraPrefsCache.init();
      await NeuraPrefsCache.prefs.clear();
      NeuraSpokenLexiconStore.instance.resetForTest();
    });

    test('stores only confirmed corrections and forgets them on wipe',
        () async {
      final store = NeuraSpokenLexiconStore.instance;
      expect(store.apply('camera hock'), 'camera hock');

      await store.remember(
        NeuraSpokenCorrection(heard: 'camera hock', meant: 'Camera Hawk'),
      );
      expect(store.apply('check camera hock'), 'check Camera Hawk');

      store.resetAfterDataWipe();
      await NeuraPrefsCache.prefs.clear();
      expect(store.apply('check camera hock'), 'check camera hock');
    });

    test('forget removes a single correction', () async {
      final store = NeuraSpokenLexiconStore.instance;
      await store.remember(
        NeuraSpokenCorrection(heard: 'neuro', meant: 'Neura'),
      );
      await store.forget('neuro');
      expect(store.apply('neuro'), 'neuro');
    });
  });
}
