import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/mood/services/mood_state_service.dart';
import 'package:neuro_companion/persona/services/neura_prompt_builder.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/persona/services/neura_conversation_mode.dart';
import 'package:neuro_companion/persona/models/neura_audience.dart';

void main() {
  test('offline prompt excludes stored mood while retaining Neura identity',
      () async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await MoodStateService.instance.setMood('anxious');
    final prompt = await NeuraPromptBuilder.instance.buildSystemMessage(
      module: 'penthouse',
      includePersistentMemory: false,
      includeCurrentMood: false,
    );
    expect(prompt, contains('You are Neura'));
    expect(prompt, contains('heart of gold'));
    expect(prompt, contains('"neutral" mood'));
    expect(prompt, isNot(contains('"anxious" mood')));
    expect(MoodStateService.instance.currentMood, 'anxious');
  });
  test('all conversation modes retain safety within the native system budget',
      () async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    for (final mode in NeuraConversationMode.values) {
      for (final audience in NeuraAudience.values) {
        final prompt = await NeuraPromptBuilder.instance.buildSystemMessage(
          module: 'penthouse',
          audience: audience,
          includePersistentMemory: false,
          includeCurrentMood: false,
          conversationMode: mode,
        );
        const suffix = '\n\nYou are running offline. Do not claim web access, '
            'saved memories or completed actions. Offer everyday support; do not '
            'diagnose or advise medication changes. No tools are available.';
        expect(utf8.encode('$prompt$suffix').length, lessThanOrEqualTo(6500),
            reason: '${mode.name}/${audience.name}');
        expect(prompt, contains('Safe Mode keeps the microphone off'));
        expect(prompt, contains('fresh user approval'));
      }
    }
  });
}
