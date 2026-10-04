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
    expect(NeuraVoiceCommand.parse('Neura, take me home'),
        NeuraVoiceCommand.openPenthouse);
    expect(NeuraVoiceCommand.parse('Hey Neura where are we?'),
        NeuraVoiceCommand.whereAmI);
    expect(NeuraVoiceCommand.parse('Neura, open dream room'),
        NeuraVoiceCommand.openDreamAtrium);
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
      'open guided support': NeuraVoiceCommand.guidedSupport,
      'i need a moment': NeuraVoiceCommand.guidedSupport,
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

  test('guided support aliases reject partial, quoted and compound speech', () {
    for (final phrase in [
      'help me through this',
      'open guided support',
      'i need a moment',
    ]) {
      expect(NeuraVoiceCommand.parse('Neura, $phrase'),
          NeuraVoiceCommand.guidedSupport);
      expect(NeuraVoiceCommand.parse('“Neura, $phrase”'), isNull);
      expect(
          NeuraVoiceCommand.parse('Neura, $phrase and open journal'), isNull);
    }
    for (final partial in [
      'Neura, help me through',
      'Neura, open guided',
      'Neura, I need',
    ]) {
      expect(NeuraVoiceCommand.parse(partial), isNull, reason: partial);
    }
  });

  test('room aliases stay distinct from screen shortcuts and match exactly',
      () {
    final examples = {
      'go home': NeuraVoiceCommand.openPenthouse,
      'open the penthouse': NeuraVoiceCommand.openPenthouse,
      'go to reflection bay': NeuraVoiceCommand.openReflectionBay,
      'open reflection': NeuraVoiceCommand.openReflectionBay,
      'go to joy lounge': NeuraVoiceCommand.openJoyLounge,
      'open joy': NeuraVoiceCommand.openJoyLounge,
      'go to mood den': NeuraVoiceCommand.openMoodDen,
      'go to dream atrium': NeuraVoiceCommand.openDreamAtrium,
      'open dream room': NeuraVoiceCommand.openDreamAtrium,
      'open dream calendar': NeuraVoiceCommand.openDreamJournal,
      'go to legacy vault': NeuraVoiceCommand.openLegacyVault,
      'open legacy': NeuraVoiceCommand.openLegacyVault,
      'where are we': NeuraVoiceCommand.whereAmI,
      'what room am i in': NeuraVoiceCommand.whereAmI,
      'which room am i in': NeuraVoiceCommand.whereAmI,
    };
    for (final entry in examples.entries) {
      expect(NeuraVoiceCommand.parse('Hey Neura, ${entry.key} please?'),
          entry.value,
          reason: entry.key);
      expect(NeuraVoiceCommand.parse(entry.key), isNull);
      expect(NeuraVoiceCommand.parse('Neura, ${entry.key} and send my journal'),
          isNull);
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
