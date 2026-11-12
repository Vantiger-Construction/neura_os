import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/persona/models/neura_audience.dart';
import 'package:neuro_companion/persona/models/neura_persona_preset.dart';
import 'package:neuro_companion/persona/services/neura_conversation_mode.dart';
import 'package:neuro_companion/persona/services/neura_persona_service.dart';
import 'package:neuro_companion/persona/services/neura_prompt_builder.dart';
import 'package:neuro_companion/planning/neura_daily_plan_screen.dart';
import 'package:neuro_companion/planning/neura_starter_steps.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/profiles/local_profile_service.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/teaching/neura_teaching_preferences.dart';
import 'package:neuro_companion/teaching/neura_teaching_service.dart';

import '../helpers/companion_memory_fixture.dart';

class _Store implements NeuraTeachingStore {
  NeuraTeachingPreferences value = const NeuraTeachingPreferences();
  Completer<void>? readGate;
  @override
  bool get authorityCurrent => true;
  @override
  Future<NeuraTeachingPreferences> read(
      {required bool Function() stillAllowed}) async {
    await readGate?.future;
    return value;
  }

  @override
  Future<void> write(NeuraTeachingPreferences value,
      {required bool Function() stillAllowed}) async {
    if (!stillAllowed()) throw StateError('Cancelled');
    this.value = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'explicit detail reaches the real prompt without enlarging local budgets',
      () async {
    final fixture = await CompanionMemoryFixture.create();
    final teaching = NeuraTeachingService.instance;
    await teaching.load();
    for (final detail in NeuraAnswerDetail.values) {
      await teaching.setAnswerDetail(
          teaching.beginChange(directUserGesture: true), detail,
          today: false);
      for (final preset in NeuraPersonaPreset.values) {
        await NeuraPersonaService.instance.update(preset.profile);
        for (final audience in NeuraAudience.values) {
          for (final mode in NeuraConversationMode.values) {
            final prompt = await NeuraPromptBuilder.instance.buildSystemMessage(
                includeCurrentMood: false,
                audience: audience,
                conversationMode: mode,
                module: 'penthouse');
            expect(prompt, contains('Default to'));
            expect(prompt,
                contains("Follow the user's requested detail for this reply"));
            expect(prompt, contains('fresh user approval'));
            expect(prompt, contains('Model output proposes actions'));
            const suffix =
                '\n\nYou are running offline. Do not claim web access, '
                'saved memories or completed actions. Offer everyday support; do not '
                'diagnose or advise medication changes. No tools are available.';
            expect(
                utf8.encode('$prompt$suffix').length, lessThanOrEqualTo(6500),
                reason:
                    '${detail.name}/${preset.name}/${audience.name}/${mode.name}');
          }
        }
      }
    }
    await teaching
        .removeAnswerDetail(teaching.beginChange(directUserGesture: true));
    final restored = await NeuraPromptBuilder.instance
        .buildSystemMessage(includeCurrentMood: false);
    expect(restored, isNot(contains('Default to')));
    fixture.disk.expectIsolation();
  });

  for (final remove in [false, true]) {
    test(
        'preference ${remove ? 'removal' : 'change'} during recall rejects stale prompt',
        () async {
      final fixture = await CompanionMemoryFixture.create();
      await fixture.disk.run(() async {
        await fixture.seed('Synthetic note for teaching recall race');
        final teaching = NeuraTeachingService.instance;
        await teaching.load();
        await teaching.setAnswerDetail(
            teaching.beginChange(directUserGesture: true),
            NeuraAnswerDetail.brief,
            today: false);

        // A fresh owner restores from encrypted storage rather than relying on
        // the writer's in-memory view. Pause only companion-note decryption.
        final reader = fixture.owner();
        fixture.crypto.pauseRead = true;
        final permission = reader.authorize(CompanionMemoryUse.prompt,
            directUserGesture: true);
        final result = expectLater(
            NeuraPromptBuilder.instance.buildSystemMessage(
                includeCurrentMood: false,
                includePersistentMemory: true,
                memoryPermission: permission),
            throwsA(isA<StateError>().having(
                (error) => error.message,
                'message',
                'Answer preferences changed while preparing the reply.')));
        await fixture.crypto.entered.future;
        try {
          final permit = teaching.beginChange(directUserGesture: true);
          if (remove) {
            await teaching.removeAnswerDetail(permit);
          } else {
            await teaching.setAnswerDetail(permit, NeuraAnswerDetail.detailed,
                today: false);
          }
        } finally {
          fixture.crypto.release();
        }
        await result;
        expect(permission.lease.isConsumed, isTrue);
        expect(teaching.current.answerDetail,
            remove ? null : NeuraAnswerDetail.detailed);
        final freshPrompt = await NeuraPromptBuilder.instance
            .buildSystemMessage(includeCurrentMood: false);
        expect(freshPrompt, isNot(contains('Default to brief answers')));
        if (!remove) {
          expect(freshPrompt, contains('Default to a fuller explanation'));
        }
        fixture.disk.expectIsolation();
      });
    });
  }

  test('profile boundary during preference load discards the entire prompt',
      () async {
    final fixture = await CompanionMemoryFixture.create();
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.disk.preferences.beforeGetAll = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    final prompt = NeuraPromptBuilder.instance
        .buildSystemMessage(includeCurrentMood: false);
    final rejected = expectLater(prompt, throwsStateError);
    await entered.future;
    // Even a false marker must gate ordinary-installation settings. This is
    // disposable synthetic storage, not an activation or ownership bypass.
    await NeuraPrefsCache.prefs.setBool(LocalProfileService.modeKey, false);
    await LocalProfileService.instance.enable(directUserGesture: true);
    release.complete();
    await rejected;
    expect(NeuraTeachingService.instance.current.isEmpty, isTrue);
    fixture.disk.preferences.beforeGetAll = null;
    await NeuraPrefsCache.prefs.remove(LocalProfileService.modeKey);
    fixture.disk.expectIsolation();
  });

  test('full wipe drains teaching storage before deleting ciphertext and keys',
      () async {
    final fixture = await CompanionMemoryFixture.create();
    await fixture.disk.run(() async {
      final teaching = NeuraTeachingService.instance;
      await teaching.load();
      final admitted = Completer<void>();
      final release = Completer<void>();
      const key = NeuraEncryptedTeachingStore.storageKey;
      fixture.disk.preferences.beforeSet = (name) async {
        if (name == 'flutter.$key') {
          admitted.complete();
          await release.future;
        }
      };
      final save = teaching.setPlanSize(
          teaching.beginChange(directUserGesture: true), NeuraPlanSize.one,
          today: false);
      final rejected = expectLater(save, throwsStateError);
      await admitted.future;
      var done = false;
      final wipe =
          NeuraDataWipeService.wipeAllLocalData().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      expect(teaching.available, isFalse);
      release.complete();
      await rejected;
      await wipe;
      await NeuraPrefsCache.prefs.reload();
      expect(NeuraPrefsCache.prefs.containsKey(key), isFalse);
      expect(teaching.current.isEmpty, isTrue);
      expect(fixture.disk.secrets.containsKey('neura.memoryGraph.seed.v2'),
          isFalse);
      fixture.disk.expectIsolation();
    });
  });

  test('starter preferences never cap user-authored plans or rewrite templates',
      () {
    expect(neuraStarterSteps(null), hasLength(3));
    expect(neuraStarterSteps(NeuraPlanSize.one), hasLength(1));
    expect(neuraStarterSteps(NeuraPlanSize.three), hasLength(3));
  });

  testWidgets(
      'planner uses the chosen size only after requesting starter steps',
      (tester) async {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraTeachingService.resetWipeGateForTesting();
    final store = _Store();
    final teaching = NeuraTeachingService.forTesting(store: store);
    addTearDown(teaching.dispose);
    await teaching.load();
    await teaching.setPlanSize(
        teaching.beginChange(directUserGesture: true), NeuraPlanSize.one,
        today: false);
    await tester.pumpWidget(
        MaterialApp(home: NeuraDailyPlanScreen(teachingService: teaching)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Synthetic goal');
    await tester.enterText(
        find.byType(TextField).last, 'My first step\nMy second step');
    await teaching.setPlanSize(
        teaching.beginChange(directUserGesture: true), NeuraPlanSize.three,
        today: true);
    await tester.pump();
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'My first step\nMy second step');
    await tester.ensureVisible(find.text('Suggest starter steps'));
    await tester.tap(find.text('Suggest starter steps'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .controller!
            .text
            .split('\n'),
        hasLength(3));
    await teaching.setPlanSize(
        teaching.beginChange(directUserGesture: true), NeuraPlanSize.one,
        today: false);
    await tester.tap(find.text('Suggest starter steps'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .controller!
            .text
            .split('\n'),
        hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late settings load cannot overwrite a newer planner draft',
      (tester) async {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraTeachingService.resetWipeGateForTesting();
    final store = _Store()..readGate = Completer<void>();
    final teaching = NeuraTeachingService.forTesting(store: store);
    addTearDown(teaching.dispose);
    await tester.pumpWidget(
        MaterialApp(home: NeuraDailyPlanScreen(teachingService: teaching)));
    await tester.ensureVisible(find.text('Suggest starter steps'));
    await tester.tap(find.text('Suggest starter steps'));
    await tester.enterText(
        find.byType(TextField).last, 'Keep this newer draft');
    store.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Keep this newer draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
