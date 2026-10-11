import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/mood/services/mood_state_service.dart';
import 'package:neuro_companion/persona/services/neura_prompt_builder.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

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
}
