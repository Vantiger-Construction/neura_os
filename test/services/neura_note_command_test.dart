import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_language.dart';
import 'package:neuro_companion/services/neura_note_command.dart';
import 'package:neuro_companion/services/neura_voice_command.dart';

void main() {
  group('adding one note', () {
    const examples = <String, (NeuraLanguage, String)>{
      'Neura, take a note: call the clinic on Monday':
          (NeuraLanguage.en, 'call the clinic on Monday'),
      'Neura take a note buy milk': (NeuraLanguage.en, 'buy milk'),
      'Hey Neura, make a note. Water the plants.':
          (NeuraLanguage.en, 'Water the plants.'),
      'Neura, note that Sam likes tea': (NeuraLanguage.en, 'Sam likes tea'),
      'Neura, toma nota: comprar leche mañana':
          (NeuraLanguage.es, 'comprar leche mañana'),
      'Oye Neura, anota que la cita es el jueves':
          (NeuraLanguage.es, 'que la cita es el jueves'),
      'Neura, prendi nota: chiamare la mamma domani':
          (NeuraLanguage.it, 'chiamare la mamma domani'),
      'Neura, notiere: morgen Mama anrufen':
          (NeuraLanguage.de, 'morgen Mama anrufen'),
      'Neura, schreib auf, dass ich Brot brauche':
          (NeuraLanguage.de, 'dass ich Brot brauche'),
      'Neura, prends note : appeler maman demain':
          (NeuraLanguage.fr, 'appeler maman demain'),
      "Neura, note : je dois appeler le médecin aujourd'hui":
          (NeuraLanguage.fr, "je dois appeler le médecin aujourd'hui"),
    };
    for (final example in examples.entries) {
      test(example.key, () {
        final command = NeuraNoteCommand.parse(example.key);
        expect(command, isNotNull);
        expect(command!.action, NeuraNoteAction.add);
        expect(command.language, example.value.$1);
        expect(command.text, example.value.$2);
      });
    }

    test('a typed request may leave out the address when it uses a colon', () {
      final command =
          NeuraNoteCommand.parse('take a note: pay rent', typed: true);
      expect(command?.text, 'pay rent');
      expect(NeuraNoteCommand.parse('take a note: pay rent'), isNull);
      expect(
        NeuraNoteCommand.parse('take a note of how I feel', typed: true),
        isNull,
      );
    });

    test('ordinary conversation is never filed as a note', () {
      for (final message in [
        'I should take a note of that',
        'Note: I am not feeling great today',
        'Neura, take a note',
        'Neura, take a notebook to school',
        'Neural, take a note: x',
        'Can Neura take a note for me?',
        'Neura, notebooks are expensive',
        '',
      ]) {
        expect(
          NeuraNoteCommand.parse(message, typed: true),
          isNull,
          reason: message,
        );
      }
    });
  });

  group('taking notes', () {
    const starts = {
      'Neura, start taking notes': NeuraLanguage.en,
      'Hey Neura, take notes please.': NeuraLanguage.en,
      'Neura, empieza a tomar notas': NeuraLanguage.es,
      'Neura, prendi appunti': NeuraLanguage.it,
      'Neura, schreib mit': NeuraLanguage.de,
      'Neura, prends des notes': NeuraLanguage.fr,
    };
    for (final entry in starts.entries) {
      test('starts: ${entry.key}', () {
        final command = NeuraNoteCommand.parse(entry.key);
        expect(command?.action, NeuraNoteAction.startTaking);
        expect(command?.language, entry.value);
      });
    }

    const stops = {
      'Neura, stop taking notes': NeuraLanguage.en,
      'Neura, deja de tomar notas.': NeuraLanguage.es,
      'Neura, smetti di prendere appunti': NeuraLanguage.it,
      'Neura, hör auf mitzuschreiben': NeuraLanguage.de,
      'Neura, arrête de prendre des notes': NeuraLanguage.fr,
    };
    for (final entry in stops.entries) {
      test('stops: ${entry.key}', () {
        final command = NeuraNoteCommand.parse(entry.key);
        expect(command?.action, NeuraNoteAction.stopTaking);
        expect(command?.language, entry.value);
      });
    }

    test('starting needs the address, even typed', () {
      expect(NeuraNoteCommand.parse('start taking notes', typed: true), isNull);
      expect(
        NeuraNoteCommand.parse('Neura, start taking notes about my day'),
        isNull,
      );
    });
  });

  test('replies exist in every language', () {
    for (final language in NeuraLanguage.values) {
      expect(NeuraNoteCommand.savedReply(language), isNotEmpty);
      expect(NeuraNoteCommand.startedReply(language), contains('Neura'));
      expect(NeuraNoteCommand.stoppedReply(language), isNotEmpty);
    }
  });

  group('voice controls in other languages', () {
    test('stop, mute, help and notes', () {
      final examples = {
        'Neura, para': NeuraVoiceCommand.stopListening,
        'Oye Neura, deja de escuchar': NeuraVoiceCommand.stopListening,
        'Ehi Neura, basta!': NeuraVoiceCommand.stopListening,
        'Neura, stopp': NeuraVoiceCommand.stopListening,
        'Neura, hör auf.': NeuraVoiceCommand.stopListening,
        'Dis Neura, arrête': NeuraVoiceCommand.stopListening,
        'Neura, deja de hablar': NeuraVoiceCommand.stopSpeaking,
        'Neura, silenzio per favore': NeuraVoiceCommand.muteReplies,
        'Hallo Neura, stumm bitte': NeuraVoiceCommand.muteReplies,
        "Neura, aide s'il te plaît": NeuraVoiceCommand.help,
        'Neura, abre mis notas, por favor': NeuraVoiceCommand.openNotes,
        'Neura, open my notes': NeuraVoiceCommand.openNotes,
      };
      for (final entry in examples.entries) {
        expect(
          NeuraVoiceCommand.parse(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('a note request is not a control', () {
      expect(NeuraVoiceCommand.parse('Neura, take a note: buy milk'), isNull);
      expect(NeuraVoiceCommand.parse('Neura, para mañana'), isNull);
    });
  });
}
