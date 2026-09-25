import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_voice_command.dart';

void main() {
  for (final command in NeuraVoiceCommand.values) {
    test('recognizes ${command.phrase} only when addressed to Neura', () {
      expect(NeuraVoiceCommand.parse('Neura, ${command.phrase}'), command);
      expect(NeuraVoiceCommand.parse(command.phrase), isNull);
    });
  }

  test('accepts wake phrase, case, spacing, politeness, and final punctuation',
      () {
    expect(
      NeuraVoiceCommand.parse('  HEY   NEURA, please open settings!  '),
      NeuraVoiceCommand.openSettings,
    );
    expect(NeuraVoiceCommand.parse('Neura stop talking please.'),
        NeuraVoiceCommand.stopSpeaking);
    expect(NeuraVoiceCommand.parse('Neura: switch to coach mode'),
        NeuraVoiceCommand.coachMode);
    expect(NeuraVoiceCommand.parse('Neura open mood check in'),
        NeuraVoiceCommand.openMood);
  });

  test('ordinary conversation and incomplete phrases do not execute controls',
      () {
    for (final phrase in [
      '',
      'Neura',
      'Please tell Neura to open settings',
      'I asked Neura to stop listening',
      'Neural open settings',
      'Hey Neura, help me plan my day',
      'Neura, open',
      'Neura, mute repl',
      '“Neura, stop listening”',
    ]) {
      expect(NeuraVoiceCommand.parse(phrase), isNull, reason: phrase);
    }
  });

  test('rejects compound, destructive, approval, and background commands', () {
    for (final phrase in [
      'Neura, open journal and send it to everyone',
      'Neura, open journal. Then delete it.',
      'Neura, delete my journal',
      'Neura, approve the cloud request',
      'Neura, remember everything',
      'Neura, disable Safe Mode',
      'Neura, start background listening',
      'Neura, run powershell',
    ]) {
      expect(NeuraVoiceCommand.parse(phrase), isNull, reason: phrase);
    }
  });
}
