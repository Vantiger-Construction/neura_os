import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_language.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';

void main() {
  group('NeuraLanguage.fromCode', () {
    test('accepts codes, regional tags, Whisper tokens and names', () {
      expect(NeuraLanguage.fromCode('es'), NeuraLanguage.es);
      expect(NeuraLanguage.fromCode('es-MX'), NeuraLanguage.es);
      expect(NeuraLanguage.fromCode('fr_CA'), NeuraLanguage.fr);
      expect(NeuraLanguage.fromCode('<|de|>'), NeuraLanguage.de);
      expect(NeuraLanguage.fromCode(' IT '), NeuraLanguage.it);
      expect(NeuraLanguage.fromCode('English'), NeuraLanguage.en);
      expect(NeuraLanguage.fromCode('Français'), NeuraLanguage.fr);
    });

    test('rejects languages Neura does not speak and junk', () {
      expect(NeuraLanguage.fromCode(null), isNull);
      expect(NeuraLanguage.fromCode(''), isNull);
      expect(NeuraLanguage.fromCode('ja'), isNull);
      expect(NeuraLanguage.fromCode('pt-BR'), isNull);
      expect(NeuraLanguage.fromCode('x' * 40), isNull);
    });
  });

  group('NeuraLanguageGuess', () {
    const samples = {
      "I'm feeling really tired today and I don't know what to do":
          NeuraLanguage.en,
      'Can you help me with this?': NeuraLanguage.en,
      'Hola, ¿cómo estás? Hoy me siento muy cansado': NeuraLanguage.es,
      'Estoy triste y necesito ayuda': NeuraLanguage.es,
      'Puedes ayudarme con esto?': NeuraLanguage.es,
      'Ciao, come stai? Oggi sono molto stanco': NeuraLanguage.it,
      'Non so cosa fare, ho bisogno di aiuto': NeuraLanguage.it,
      'Hallo, wie geht es dir? Ich bin heute sehr müde': NeuraLanguage.de,
      'Ich weiß nicht, was ich machen soll': NeuraLanguage.de,
      'Kannst du mir helfen?': NeuraLanguage.de,
      "Bonjour, comment ça va ? Je suis très fatigué aujourd'hui":
          NeuraLanguage.fr,
      "Je ne sais pas quoi faire, j'ai besoin d'aide": NeuraLanguage.fr,
      "Tu peux m'aider ?": NeuraLanguage.fr,
    };

    for (final sample in samples.entries) {
      test('recognizes ${sample.value.englishName}: "${sample.key}"', () {
        expect(NeuraLanguageGuess.of(sample.key), sample.value);
      });
    }

    test('stays silent when there is too little to go on', () {
      expect(NeuraLanguageGuess.of(''), isNull);
      expect(NeuraLanguageGuess.of('ok'), isNull);
      expect(NeuraLanguageGuess.of('Camera Hawk'), isNull);
      expect(NeuraLanguageGuess.of('gracias'), isNull);
      expect(NeuraLanguageGuess.of('12345 !!!'), isNull);
    });
  });

  group('NeuraLanguageCue', () {
    test('English and unknown turns add no note', () {
      expect(NeuraLanguageCue.forLanguage(null), isEmpty);
      expect(NeuraLanguageCue.forLanguage(NeuraLanguage.en), isEmpty);
    });

    test('every other language names itself and fits the cue budget', () {
      for (final language in NeuraLanguage.values) {
        if (language == NeuraLanguage.en) continue;
        final cue = NeuraLanguageCue.forLanguage(language);
        expect(cue, contains(language.englishName));
        expect(cue, contains('Reply only in'));
        // Leaves most of the budget for the spoken and emotion notes.
        expect(
          utf8.encode(cue).length,
          lessThan(NeuraOllamaChat.maxCueBytes ~/ 2),
        );
      }
    });
  });
}
