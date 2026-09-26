import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_voice_command.dart';

void main() {
  for (final command in NeuraVoiceCommand.values) {
    test('recognizes ${command.phrase} only when addressed to Neura', () {
      expect(NeuraVoiceCommand.parse('Neura, ${command.phrase}'), command);
      expect(NeuraVoiceCommand.parse(command.phrase), isNull);
      expect(NeuraVoiceCommand.parse('Neura, ${command.phrase} and send it'),
          isNull);
      expect(NeuraVoiceCommand.parse('“Neura, ${command.phrase}”'), isNull);
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

  test('recognizes navigation, scrolling, and context aliases exactly', () {
    final examples = {
      'show mood history': NeuraVoiceCommand.openMoodHistory,
      'show weekly review': NeuraVoiceCommand.openWeeklyReview,
      'open dream calendar': NeuraVoiceCommand.openDreamJournal,
      'open focus office': NeuraVoiceCommand.openFocus,
      'open my quests': NeuraVoiceCommand.openQuests,
      'open life timeline': NeuraVoiceCommand.openTimeline,
      'open accessibility settings': NeuraVoiceCommand.openAccessibility,
      'open appearance': NeuraVoiceCommand.openThemes,
      'open privacy settings': NeuraVoiceCommand.openPrivacy,
      'open notification settings': NeuraVoiceCommand.openNotifications,
      'open getting started': NeuraVoiceCommand.openHelp,
      'choose a companion': NeuraVoiceCommand.chooseCompanion,
      'page up': NeuraVoiceCommand.scrollUp,
      'page down': NeuraVoiceCommand.scrollDown,
      'go to first message': NeuraVoiceCommand.scrollToTop,
      'show latest message': NeuraVoiceCommand.scrollToBottom,
      'remove selected file': NeuraVoiceCommand.removeSelectedContext,
      'don’t use memories': NeuraVoiceCommand.excludeMemories,
    };
    for (final entry in examples.entries) {
      expect(NeuraVoiceCommand.parse('Hey Neura, ${entry.key} please!'),
          entry.value,
          reason: entry.key);
    }
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
      'Neura, mark all quests complete',
      'Neura, generate and share my weekly review',
      'Neura, enable all notifications',
      'Neura, include all memories',
      'Neura, remove all saved memories',
    ]) {
      expect(NeuraVoiceCommand.parse(phrase), isNull, reason: phrase);
    }
  });
}
