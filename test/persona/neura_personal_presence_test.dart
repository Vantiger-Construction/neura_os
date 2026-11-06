import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/avatar/motion/neura_motion_engine.dart';
import 'package:neuro_companion/persona/agents/agent_persona_catalog.dart';
import 'package:neuro_companion/persona/models/neura_audience.dart';
import 'package:neuro_companion/persona/models/neura_persona_preset.dart';
import 'package:neuro_companion/persona/models/persona_profile.dart';
import 'package:neuro_companion/persona/screens/persona_tuning_screen.dart';
import 'package:neuro_companion/persona/services/neura_behavior_adapter.dart';
import 'package:neuro_companion/persona/services/neura_conversation_mode.dart';
import 'package:neuro_companion/persona/services/neura_persona_service.dart';
import 'package:neuro_companion/persona/services/neura_prompt_builder.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _RejectingPreferences extends SharedPreferencesStorePlatform {
  _RejectingPreferences(this.original);
  final SharedPreferencesStorePlatform original;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
  @override
  Future<Map<String, Object>> getAll() => original.getAll();
  @override
  Future<bool> clear() => original.clear();
  @override
  Future<bool> remove(String key) => original.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = NeuraPersonaService.instance;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    NeuraMotion.instance.stop();
    await NeuraPrefsCache.prefs.clear();
    service.resetAfterDataWipe();
  });
  tearDown(() {
    NeuraMotion.instance.stop();
    service.resetAfterDataWipe();
  });

  test(
      'distinct choices survive reload and reach offline prompts within budget',
      () async {
    final prompts = <String>{};
    for (final preset in NeuraPersonaPreset.values) {
      expect(await service.update(preset.profile), isTrue);
      // Clear only in-memory state to simulate a fresh service load.
      service.resetAfterDataWipe();
      await service.load();
      expect(service.current.toMap(), preset.profile.toMap());
      for (final mode in NeuraConversationMode.values) {
        for (final audience in NeuraAudience.values) {
          final prompt = await NeuraPromptBuilder.instance.buildSystemMessage(
            module: 'penthouse',
            audience: audience,
            conversationMode: mode,
            includeCurrentMood: false,
          );
          const suffix =
              '\n\nYou are running offline. Do not claim web access, '
              'saved memories or completed actions. Offer everyday support; do not '
              'diagnose or advise medication changes. No tools are available.';
          expect(utf8.encode('$prompt$suffix').length, lessThanOrEqualTo(6500),
              reason: '${preset.name}/${mode.name}/${audience.name}');
          expect(prompt, contains('fresh user approval'));
          expect(prompt, contains('Safe Mode keeps the microphone off'));
          if (mode == NeuraConversationMode.balanced &&
              audience == NeuraAudience.adult) {
            prompts.add(prompt);
          }
        }
      }
    }
    expect(prompts.length, NeuraPersonaPreset.values.length);
  });

  test('stored mood adaptation reaches wording without changing chosen style',
      () {
    final chosen = NeuraPersonaPreset.playful.profile;
    final style = NeuraBehaviorAdapter().computeStyle(
      persona: chosen,
      mood: 'tired',
      agent: AgentPersonaCatalog.byId(AgentPersonaCatalog.generalId),
    );
    expect(style.energyLevel, lessThan(chosen.energy));
    expect(style.systemPromptSnippet, contains('steady and grounded energy'));
    expect(style.systemPromptSnippet, isNot(contains('Bring high energy')));
    expect(style.systemPromptSnippet, isNot(contains('Use playful humor')));
    expect(chosen.energy, 0.8);
  });

  test('a rejected save retains the confirmed profile across prompt reload',
      () async {
    await service.update(NeuraPersonaPreset.calm.profile);
    final original = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = _RejectingPreferences(original);
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    expect(await service.update(NeuraPersonaPreset.playful.profile), isFalse);
    expect(service.current.toMap(), NeuraPersonaPreset.calm.profile.toMap());
    await service.load();
    expect(service.current.toMap(), NeuraPersonaPreset.calm.profile.toMap());
  });

  test('personalities produce different bounded motion for identical activity',
      () {
    NeuraMotionEngine engine(NeuraPersonaPreset preset) =>
        NeuraMotionEngine(random: Random(7))
          ..setPhase(NeuraBodyPhase.listening)
          ..setPersonality(
            energy: preset.profile.energy,
            warmth: preset.profile.warmth,
            playfulness: preset.profile.humor,
          );
    final calm = engine(NeuraPersonaPreset.calm);
    final playful = engine(NeuraPersonaPreset.playful);
    var difference = 0.0;
    for (var i = 0; i < 600; i++) {
      final a = calm.tick(1 / 60);
      final b = playful.tick(1 / 60);
      difference += (a.scale - b.scale).abs() + (a.lean - b.lean).abs();
      for (final pose in [a, b]) {
        expect(pose.isFinite, isTrue);
        expect(pose.scale, inInclusiveRange(0.85, 1.2));
        expect(pose.lean.abs(), lessThan(0.3));
      }
    }
    expect(difference, greaterThan(0.1));
    expect(calm.phase, NeuraBodyPhase.listening);
    expect(playful.phase, NeuraBodyPhase.listening);
    expect(calm.energy, playful.energy);
    expect(calm.mood, playful.mood);
    for (final e in [calm, playful]) {
      e.setFrozen(true);
      e.setPersonality(energy: 1, warmth: 1, playfulness: 1);
      expect(e.tick(1 / 60), same(NeuraPose.neutral));
      e.setMotionLevel(NeuraBodyMotionLevel.still);
      e.setFrozen(false);
      expect(e.tick(1 / 60), same(NeuraPose.neutral));
    }
  });

  test('invalid preferences and motion inputs are finite and bounded', () {
    final profile = PersonaProfile.fromMap({
      'warmth': double.nan,
      'energy': double.infinity,
      'humor': -8,
      'directness': 9,
      'depth': 'unexpected',
    });
    expect(profile.toMap(),
        PersonaProfile.neutral().copyWith(humor: 0, directness: 1).toMap());
    final engine = NeuraMotionEngine()
      ..setPersonality(
          energy: double.nan, warmth: double.infinity, playfulness: -9);
    expect(engine.personaEnergy, 0.5);
    expect(engine.personaWarmth, 0.6);
    expect(engine.playfulness, 0);
    expect(engine.tick(0.1).isFinite, isTrue);
  });

  testWidgets(
      'draft previews stay local until saved; reset and wipe reach motion',
      (tester) async {
    final previousSafeMode = SafeBoot.instance.safeMode.value;
    final previousRecovery = SafeBoot.instance.restartRequired.value;
    addTearDown(() {
      SafeBoot.instance.safeMode.value = previousSafeMode;
      SafeBoot.instance.restartRequired.value = previousRecovery;
    });
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraMotion.instance.start();
    await tester.pumpWidget(const MaterialApp(home: PersonaTuningScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playful spark'));
    await tester.pumpAndSettle();
    expect(find.text(personaStylePreview(NeuraPersonaPreset.playful.profile)),
        findsOneWidget);
    expect(service.current.energy, 0.5);
    expect(NeuraMotion.instance.engine.personaEnergy, 0.5);
    final save = find.widgetWithText(ElevatedButton, 'Save persona');
    await tester.scrollUntilVisible(save, 400);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(service.current.energy, 0.8);
    expect(NeuraMotion.instance.engine.personaEnergy, 0.8);
    expect(NeuraMotion.instance.engine.playfulness, 0.8);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset draft to balanced'));
    await tester.pumpAndSettle();
    expect(service.current.energy, 0.8);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(service.current.toMap(), PersonaProfile.neutral().toMap());
    expect(NeuraMotion.instance.engine.personaEnergy, 0.5);

    SafeBoot.instance.safeMode.value = true;
    await service.update(NeuraPersonaPreset.calm.profile);
    expect(NeuraMotion.instance.live.value, isFalse);
    expect(NeuraMotion.instance.sample(), same(NeuraPose.neutral));
    await NeuraPrefsCache.prefs.clear();
    service.resetAfterDataWipe();
    expect(NeuraMotion.instance.engine.personaEnergy, 0.5);
    expect(NeuraMotion.instance.live.value, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
