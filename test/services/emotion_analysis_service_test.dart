import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/emotion_analysis_service.dart';

void main() {
  const reader = EmotionAnalysisService();
  String? primary(String text) => reader.read(text).primary;

  group('reads the main feeling', () {
    final cases = <String, String>{
      'I got the job!!': 'joy',
      "I'm so excited for the weekend": 'joy',
      'Honestly I feel really sad today': 'sadness',
      "I'm not happy at all": 'sadness',
      'My dad passed away last week': 'grief',
      'We lost our dog this morning': 'grief',
      "I'm so fed up with my landlord, this is unfair": 'anger',
      "I can't stop worrying about the results": 'anxiety',
      'I have a test tomorrow and I am really nervous': 'anxiety',
      "There's so much to do and I can't cope": 'overwhelm',
      "I don't know where to start with all this": 'overwhelm',
      "I'm completely burnt out": 'exhaustion',
      'Running on empty this week': 'exhaustion',
      'I feel so lonely, nobody to talk to': 'loneliness',
      "I'm such an idiot, it was all my fault": 'shame',
      'I am so embarrassed about what I said': 'shame',
    };
    cases.forEach((text, expected) {
      test(text, () => expect(primary(text), expected));
    });
  });

  group('does not invent feelings in ordinary messages', () {
    for (final text in [
      'What time is it in Tokyo?',
      'Let me sit down and plan the week',
      'Can you help me write an email to my boss?',
      "That's great, thanks",
      'This stupid printer keeps jamming',
      'My phone died, can you remind me later?',
      'I lost my keys again',
      "I'm tired of this song, play something else",
      "I'm not worried about it",
      'How do I make pasta for two?',
      '',
    ]) {
      test('"$text"', () {
        final read = reader.read(text);
        expect(read.primary, isNull, reason: '$read');
        expect(read.promptCue, isEmpty);
      });
    }
  });

  test('negation flips joy but cancels negative feelings', () {
    expect(primary('not happy'), 'sadness');
    expect(primary("I'm not anxious, just curious"), isNull);
    expect(primary("I wasn't scared at all"), isNull);
  });

  test('clause breaks stop negation', () {
    expect(primary("I'm not sick, but I'm really anxious"), 'anxiety');
  });

  test('mixed feelings report a secondary', () {
    final read = reader.read(
        "I'm relieved it's over but so exhausted and kind of anxious too");
    expect(read.primary, isNotNull);
    expect(read.secondary, isNotNull);
    expect({read.primary, read.secondary}, contains('exhaustion'));
  });

  test('intensity rises with intensifiers and exclamation', () {
    final mild = reader.read("I'm a bit nervous");
    final strong = reader.read("I'm SO SO nervous!!");
    expect(strong.intensity, greaterThan(mild.intensity));
    expect(strong.promptCue, contains('very anxious'));
  });

  test('sarcasm is not read as joy when something is wrong', () {
    expect(
        primary('Oh great, another deadline and I am so stressed'), 'anxiety');
  });

  group('masking', () {
    test("\"I'm fine...\" alone is flagged gently", () {
      final read = reader.read("I'm fine...");
      expect(read.masked, isTrue);
      expect(read.primary, isNull);
      expect(read.promptCue, contains('check in gently'));
    });

    test("\"I'm fine\" with other signals keeps the real feeling", () {
      final read =
          reader.read("I'm fine, just really tired and nobody cares anyway");
      expect(read.masked, isTrue);
      expect(read.primary, 'loneliness');
      expect(read.promptCue, contains("though they say they're fine"));
    });

    test('a plain "I\'m fine, thanks" is not flagged', () {
      final read = reader.read("I'm fine, thanks for asking");
      expect(read.masked, isFalse);
      expect(read.promptCue, isEmpty);
    });
  });

  test('cue is tentative and phrased as a hint', () {
    final cue = reader.read('I feel really sad').promptCue;
    expect(cue, startsWith('They sound'));
    expect(cue, contains('Meet that first'));
  });

  test('every cue fits the declared byte bound', () {
    for (final text in [
      "I'm fine but SO overwhelmed and exhausted!!",
      'I feel so lonely and ashamed, but I am fine',
      "I'm fine...",
    ]) {
      expect(utf8.encode(reader.read(text).promptCue).length,
          lessThanOrEqualTo(EmotionRead.maxCueBytes));
    }
    expect(EmotionRead.maxCueBytes, lessThan(100));
  });

  test('legacy single-label API still works', () async {
    expect(await reader.analyzeEmotion('I am so happy'), 'joy');
    expect(await reader.analyzeEmotion('What is the weather?'), 'neutral');
  });

  group('emotional continuity offline', () {
    test('the newest feeling wins when it is clear', () {
      final cue = reader.offlineCue(
        newest: "I'm so stressed about tomorrow",
        hiddenUserTurns: ['I feel really lonely lately'],
      );
      expect(cue, startsWith('They sound'));
      expect(cue, contains('anxious'));
    });

    test('a feeling that scrolled out of view is gently recalled', () {
      final cue = reader.offlineCue(
        newest: 'Anyway, what should I cook tonight?',
        hiddenUserTurns: [
          'Can you help with an email?',
          "I'm really dreading my exam tomorrow, so nervous",
          'Thanks, that looks good',
        ],
      );
      expect(cue, EmotionAnalysisService.earlierCue('anxious'));
    });

    test('the most recent earlier feeling is chosen', () {
      final cue = reader.offlineCue(
        newest: 'ok',
        hiddenUserTurns: [
          'I was so happy this morning!!',
          'Now I feel really lonely, nobody to talk to',
        ],
      );
      expect(cue, contains('lonely'));
    });

    test('faint or absent earlier feelings produce no cue', () {
      expect(
          reader.offlineCue(
            newest: 'What time is it?',
            hiddenUserTurns: ['Let me sit down', "I'm fine, thanks"],
          ),
          isEmpty);
      expect(reader.offlineCue(newest: 'Hello'), isEmpty);
    });

    test('earlier cues fit the shared byte bound', () {
      for (final feeling in EmotionRead.adjectives.values) {
        expect(utf8.encode(EmotionAnalysisService.earlierCue(feeling)).length,
            lessThanOrEqualTo(EmotionRead.maxCueBytes));
      }
    });

    test('visible tail counts only turns the model still sees', () {
      final history = [
        {'role': 'user', 'content': 'a'},
        {'role': 'assistant', 'content': 'b'},
        {'role': 'user', 'content': 'c'},
        {'role': 'assistant', 'content': 'd'},
        {'role': 'user', 'content': 'e'},
      ];
      // Model sees a thread brief plus the last three turns.
      final visible = [
        {'role': 'user', 'content': 'brief'},
        {'role': 'user', 'content': 'c'},
        {'role': 'assistant', 'content': 'd'},
        {'role': 'user', 'content': 'e'},
      ];
      expect(EmotionAnalysisService.visibleTailLength(history, visible), 3);
      expect(EmotionAnalysisService.visibleTailLength(history, history), 5);
      expect(EmotionAnalysisService.visibleTailLength(history, const []), 0);
    });
  });
}
