import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/persona/models/neura_audience.dart';
import 'package:neuro_companion/persona/services/neura_audience_service.dart';
import 'package:neuro_companion/persona/services/neura_prompt_builder.dart';
import 'package:neuro_companion/services/neura_chat_policy.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  test(
      'each known room id produces a system prompt traceable to that room, '
      'not identical text regardless of room', () async {
    final prompts = <String, String>{};
    for (final roomId in NeuraChatPolicy.knownRoomIds) {
      prompts[roomId] = await NeuraPromptBuilder.instance.buildSystemMessage(
        module: roomId,
        includePersistentMemory: false,
      );
    }

    // Every room's prompt must actually differ from every other room's.
    final distinctPrompts = prompts.values.toSet();
    expect(distinctPrompts.length, prompts.length);

    // And each room's text should plausibly relate to that room, not just
    // be different for an unrelated reason.
    expect(prompts['mood_den'], contains('Mood Den'));
    expect(prompts['dream_atrium'], contains('Dream Atrium'));
    expect(prompts['reflection_bay'], contains('Reflection Bay'));
    expect(prompts['joy_lounge'], contains('Joy Lounge'));
    expect(prompts['legacy_vault'], contains('Legacy Vault'));
  });

  test('an unrecognized module hint does not throw and adds no module text',
      () async {
    final withUnknownModule =
        await NeuraPromptBuilder.instance.buildSystemMessage(
      module: 'not_a_real_room',
      includePersistentMemory: false,
    );
    final withNoModule = await NeuraPromptBuilder.instance.buildSystemMessage(
      includePersistentMemory: false,
    );

    expect(withUnknownModule, withNoModule);
  });

  group('audience safety profile reaches the outgoing system prompt', () {
    test('a child audience adds an explicit child-safety instruction',
        () async {
      final prompt = await NeuraPromptBuilder.instance.buildSystemMessage(
        audience: NeuraAudience.child,
        includePersistentMemory: false,
      );

      expect(prompt, contains('CHILD'));
      expect(prompt, contains('trusted grown-up'));
    });

    test('a teen audience adds a distinct teen-safety instruction', () async {
      final prompt = await NeuraPromptBuilder.instance.buildSystemMessage(
        audience: NeuraAudience.teen,
        includePersistentMemory: false,
      );

      expect(prompt, contains('TEENAGER'));
    });

    test('an adult audience (and no audience) adds crisis-care guidance',
        () async {
      final adultPrompt = await NeuraPromptBuilder.instance.buildSystemMessage(
        audience: NeuraAudience.adult,
        includePersistentMemory: false,
      );
      final noAudiencePrompt =
          await NeuraPromptBuilder.instance.buildSystemMessage(
        includePersistentMemory: false,
      );

      expect(adultPrompt, isNot(contains('CHILD')));
      expect(adultPrompt, isNot(contains('TEENAGER')));
      expect(adultPrompt, contains('immediate crisis resources'));
      expect(adultPrompt, noAudiencePrompt);
    });

    test(
        'the kids chat screen entry point (forcing the global audience to '
        'child) reaches the outgoing system prompt end-to-end', () async {
      // Mirrors exactly what KidsNeuraChatScreen._forceChildAudience() and
      // NeuraAiService.streamReply do together: the screen forces the
      // global, persisted NeuraAudienceService toggle, and the chat call
      // site reads it back for the outgoing system prompt.
      await NeuraAudienceService.instance.load();
      final previous = NeuraAudienceService.instance.currentAudience;
      await NeuraAudienceService.instance.setAudience(NeuraAudience.child);
      addTearDown(
        () => NeuraAudienceService.instance.setAudience(previous),
      );

      final audience = NeuraAudienceService.instance.currentAudience;
      final prompt = await NeuraPromptBuilder.instance.buildSystemMessage(
        audience: audience,
        module: 'penthouse',
        includePersistentMemory: false,
      );

      expect(audience, NeuraAudience.child);
      expect(prompt, contains('CHILD'));
    });
  });
}
