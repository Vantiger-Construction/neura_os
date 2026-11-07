import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/persona/models/neura_persona_preset.dart';
import 'package:neuro_companion/persona/screens/persona_tuning_screen.dart';
import 'package:neuro_companion/persona/services/neura_persona_service.dart';
import 'package:neuro_companion/profiles/local_profile_gate.dart';
import 'package:neuro_companion/profiles/local_profile_service.dart';
import 'package:neuro_companion/profiles/local_profile_workspace.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/companion_memory_fixture.dart';
import '../helpers/local_profile_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'setup information keeps the ordinary app and style controls usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = (await tester.runAsync(CompanionMemoryFixture.create))!;
    await tester.runAsync(() async {
      await fixture.seed('Synthetic ordinary memory');
      await NeuraPrefsCache.prefs.setString('neura_persona_profile_v1',
          jsonEncode(NeuraPersonaPreset.calm.profile.toMap()));
    });
    final permission = fixture.grant(CompanionMemoryUse.prompt);
    final preferences = Map.of(fixture.disk.preferences.data);
    final secrets = Map.of(fixture.disk.secrets);
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => LocalProfileGate(child: child!),
        home: const PersonaTuningScreen()));
    await tester.pumpAndSettle();
    expect(find.text(LocalProfileService.setupPausedMessage), findsOneWidget);
    expect(find.text('Set up separate local profiles'), findsNothing);
    await tester.tap(find.text('About separate local profiles'));
    await tester.pumpAndSettle();
    expect(find.text('Separate profile setup is paused'), findsOneWidget);
    expect(find.textContaining('no safe return'), findsOneWidget);
    expect(find.text('Enable local profiles'), findsNothing);
    expect(find.text('Erase all local data'), findsNothing);
    await tester.tap(find.text('Keep using my Neura'));
    await tester.pumpAndSettle();
    expect(find.text('Your Neura'), findsOneWidget);
    expect(LocalProfileService.instance.enabled, isFalse);
    expect(fixture.disk.preferences.data, preferences);
    expect(fixture.disk.secrets, secrets);
    permission.requireCurrent();
    permission.revoke();

    // Pausing separate profiles must leave the ordinary personality editable.
    await tester.ensureVisible(find.text('Playful spark'));
    await tester.tap(find.text('Playful spark'));
    final save = find.widgetWithText(ElevatedButton, 'Save persona');
    await tester.scrollUntilVisible(save, 400);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(NeuraPersonaService.instance.current.toMap(),
        NeuraPersonaPreset.playful.profile.toMap());
    expect(NeuraPrefsCache.prefs.containsKey(LocalProfileService.modeKey),
        isFalse);
    expect(NeuraPrefsCache.prefs.containsKey(LocalProfileService.storageKey),
        isFalse);
    for (final entry in preferences.entries) {
      if (entry.key != 'flutter.neura_persona_profile_v1') {
        expect(fixture.disk.preferences.data[entry.key], entry.value);
      }
    }
    expect(fixture.disk.secrets, secrets);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    fixture.disk.expectIsolation();
  });

  testWidgets(
      'existing workspace explains retained data and rejects stale erase',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = (await tester.runAsync(CompanionMemoryFixture.create))!;
    late final LocalProfileService service;
    await tester.runAsync(() async {
      service = LocalProfileService.forTesting(stopSession: () async {});
      await fixture.seed('Synthetic retained memory');
      await seedExistingLocalProfileRegistry();
      expect(await service.load(), isTrue);
    });
    addTearDown(service.dispose);
    final preferences = Map.of(fixture.disk.preferences.data);
    final secrets = Map.of(fixture.disk.secrets);
    final clears = fixture.disk.preferences.clearCalls;
    await tester
        .pumpWidget(MaterialApp(home: LocalProfileWorkspace(service: service)));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('A safe return to the full app is still pending'),
        findsOneWidget);
    expect(find.text('Erase all local Neura data'), findsNothing);
    await tester.scrollUntilVisible(find.text('Data deletion'), 200);
    await tester.tap(find.text('Data deletion'));
    await tester.pumpAndSettle();
    final erase = find.text('Erase all local Neura data');
    await tester.ensureVisible(erase);
    await tester.pumpAndSettle();
    await tester.tap(erase);
    await tester.pumpAndSettle();
    expect(find.textContaining('This cannot be undone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.disk.preferences.data, preferences);
    expect(fixture.disk.secrets, secrets);

    await tester.tap(erase);
    await tester.pumpAndSettle();
    await tester.runAsync(service.lock);
    await tester.tap(find.text('Erase all local data'));
    await tester.pumpAndSettle();
    expect(fixture.disk.preferences.data, preferences);
    expect(fixture.disk.secrets, secrets);
    expect(fixture.disk.preferences.clearCalls, clears);
    expect(SafeBoot.instance.safeMode.value, isFalse);
    expect(service.enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    fixture.disk.expectIsolation();
  });
}
