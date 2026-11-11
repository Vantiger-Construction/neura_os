import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/persona/models/neura_audience.dart';
import 'package:neuro_companion/persona/models/neura_persona_preset.dart';
import 'package:neuro_companion/profiles/local_profile_service.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/companion_memory_fixture.dart';
import '../helpers/local_profile_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CompanionMemoryFixture fixture;
  late LocalProfileService service;
  Future<void> seed() async {
    await seedExistingLocalProfileRegistry();
    expect(await service.load(), isTrue);
    for (final entry in [
      ('Alex', NeuraPersonaPreset.calm),
      ('Blair', NeuraPersonaPreset.playful)
    ]) {
      expect(
          await service.create(
              label: entry.$1,
              persona: entry.$2.profile,
              audience: NeuraAudience.adult,
              directUserGesture: true),
          isTrue);
    }
  }

  setUp(() async {
    fixture = await CompanionMemoryFixture.create();
    service = LocalProfileService.forTesting(stopSession: () async {});
    addTearDown(service.dispose);
  });

  test('new setup cannot strand existing encrypted records or change authority',
      () async {
    await fixture.seed('Synthetic installation memory to preserve');
    final permission = fixture.grant(CompanionMemoryUse.prompt);
    final crypto = await MemoryCrypto.demo();
    final encrypted =
        await crypto.encryptJson({'text': 'Synthetic installation journal'});
    final journal = await fixture.disk.seed(
        '${fixture.disk.documents.path}/neura_memory/synthetic-journal',
        encrypted);
    await NeuraPrefsCache.prefs
        .setString('neura_persona_profile_v1', 'Synthetic original style');
    final preferences = Map.of(fixture.disk.preferences.data);
    final secrets = Map.of(fixture.disk.secrets);
    var stops = 0;
    final blocked = LocalProfileService.forTesting(stopSession: () async {
      stops++;
    });
    addTearDown(blocked.dispose);

    expect(await blocked.enable(directUserGesture: true), isFalse);
    expect(blocked.enabled, isFalse);
    expect(blocked.active, isNull);
    expect(stops, 0);
    expect(fixture.disk.preferences.data, preferences);
    expect(fixture.disk.secrets, secrets);
    permission.requireCurrent();
    expect(await journal.readAsString(), encrypted);
    expect(await crypto.decryptJson(encrypted),
        {'text': 'Synthetic installation journal'});
    fixture.disk.expectIsolation();
  });

  test('a previously committed registry stays gated without its sentinel',
      () async {
    await seedExistingLocalProfileRegistry(withSentinel: false);
    await NeuraPrefsCache.prefs
        .setString('neura_persona_profile_v1', 'synthetic legacy preferences');
    final preferences = Map.of(fixture.disk.preferences.data);
    expect(await service.enable(directUserGesture: true), isFalse);
    expect(service.active, isNull);
    expect(service.enabled, isTrue);
    expect(fixture.disk.preferences.data, preferences);
    expect(NeuraPrefsCache.prefs.containsKey(LocalProfileService.modeKey),
        isFalse);
    expect(await service.load(), isTrue);
    expect(service.profiles, isEmpty);
    expect(NeuraPrefsCache.prefs.getString('neura_persona_profile_v1'),
        'synthetic legacy preferences');
  });

  test('setup refusal never calls unavailable storage or stops ordinary owners',
      () async {
    final preferences = Map.of(fixture.disk.preferences.data);
    final secrets = Map.of(fixture.disk.secrets);
    var storageCalls = 0;
    fixture.disk.preferences.beforeGetAll = () async {
      storageCalls++;
      throw StateError('Synthetic read failure');
    };
    fixture.disk.preferences.beforeSetValue = (_) async {
      storageCalls++;
      throw StateError('Synthetic write failure');
    };
    fixture.disk.preferences.beforeRemove = (_) async {
      storageCalls++;
      throw StateError('Synthetic removal failure');
    };
    addTearDown(() {
      fixture.disk.preferences.beforeGetAll = null;
      fixture.disk.preferences.beforeSetValue = null;
      fixture.disk.preferences.beforeRemove = null;
    });
    var stops = 0;
    final blocked = LocalProfileService.forTesting(stopSession: () async {
      stops++;
    });
    addTearDown(blocked.dispose);
    final epoch = blocked.epoch;
    for (final gesture in [false, true]) {
      expect(await blocked.enable(directUserGesture: gesture), isFalse);
    }
    blocked.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(await blocked.enable(directUserGesture: true), isFalse);
    blocked.didChangeAppLifecycleState(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = true;
    expect(await blocked.enable(directUserGesture: true), isFalse);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = true;
    expect(await blocked.enable(directUserGesture: true), isFalse);
    SafeBoot.instance.restartRequired.value = false;
    expect(blocked.enabled, isFalse);
    expect(blocked.epoch, epoch);
    expect(blocked.error, LocalProfileService.setupPausedMessage);
    expect(stops, 0);
    expect(storageCalls, 0);
    expect(fixture.disk.preferences.data, preferences);
    expect(fixture.disk.secrets, secrets);
  });

  test('setup hold preserves an already-selected workspace session', () async {
    await seed();
    await service.select(service.profiles.first.id, directUserGesture: true);
    final active = service.active;
    final epoch = service.epoch;
    final preferences = Map.of(fixture.disk.preferences.data);
    final secrets = Map.of(fixture.disk.secrets);
    expect(await service.enable(directUserGesture: true), isFalse);
    expect(service.active, same(active));
    expect(service.epoch, epoch);
    expect(service.canUseSession, isTrue);
    expect(fixture.disk.preferences.data, preferences);
    expect(fixture.disk.secrets, secrets);
  });

  test(
      'two explicit profiles retain styles; encrypted restart stays unselected',
      () async {
    await seed();
    final alex = service.profiles.first;
    final blair = service.profiles.last;
    expect(await service.select(alex.id, directUserGesture: true), isTrue);
    expect(service.active!.persona.toMap(),
        NeuraPersonaPreset.calm.profile.toMap());
    expect(await service.select(blair.id, directUserGesture: true), isTrue);
    expect(service.active!.persona.toMap(),
        NeuraPersonaPreset.playful.profile.toMap());
    final raw =
        NeuraPrefsCache.prefs.getString(LocalProfileService.storageKey)!;
    expect(raw, isNot(contains('Alex')));
    expect(raw, isNot(contains('warmth')));
    final restarted = LocalProfileService.forTesting(stopSession: () async {});
    addTearDown(restarted.dispose);
    expect(await restarted.load(), isTrue);
    expect(restarted.active, isNull);
    expect(restarted.profiles.map((p) => p.label), ['Alex', 'Blair']);
    expect(await restarted.select(alex.id, directUserGesture: true), isTrue);
    expect(restarted.active!.persona.toMap(), alex.persona.toMap());
  });

  test('rejected and misreported saves recover confirmed disk state', () async {
    await seed();
    final alex = service.profiles.first;
    await service.select(alex.id, directUserGesture: true);
    final original =
        NeuraPrefsCache.prefs.getString(LocalProfileService.storageKey);
    fixture.disk.preferences.refusedWrites
        .add('flutter.${LocalProfileService.storageKey}');
    expect(
        await service.update(NeuraPersonaPreset.practical.profile,
            expectedId: alex.id, expectedEpoch: service.epoch),
        isFalse);
    expect(service.active, isNull);
    fixture.disk.preferences.refusedWrites.clear();
    expect(await service.load(), isTrue);
    expect(NeuraPrefsCache.prefs.getString(LocalProfileService.storageKey),
        original);
    await service.select(alex.id, directUserGesture: true);
    expect(service.active!.persona.toMap(), alex.persona.toMap());
    // A backend may persist but return false. Stay locked, then recover what
    // actually survived, rather than writing a stale rollback over it.
    fixture.disk.preferences.misreportedWrites
        .add('flutter.${LocalProfileService.storageKey}');
    expect(
        await service.update(NeuraPersonaPreset.practical.profile,
            expectedId: alex.id, expectedEpoch: service.epoch),
        isFalse);
    expect(service.active, isNull);
    fixture.disk.preferences.misreportedWrites.clear();
    expect(await service.load(), isTrue);
    await service.select(alex.id, directUserGesture: true);
    expect(service.active!.persona.toMap(),
        NeuraPersonaPreset.practical.profile.toMap());
  });

  test('stale editor and stale selection cannot cross a profile boundary',
      () async {
    await seed();
    final alex = service.profiles.first.id;
    final blair = service.profiles.last.id;
    await service.select(alex, directUserGesture: true);
    final oldEpoch = service.epoch;
    await service.select(blair, directUserGesture: true);
    expect(
        await service.update(NeuraPersonaPreset.practical.profile,
            expectedId: alex, expectedEpoch: oldEpoch),
        isFalse);
    await service.select(blair, directUserGesture: true);
    expect(service.active!.persona.toMap(),
        NeuraPersonaPreset.playful.profile.toMap());
    final selected = service.select(alex, directUserGesture: true);
    await service.lock();
    expect(await selected, isFalse);
    expect(service.active, isNull);
  });

  test(
      'background, Safe Mode and recovery revoke selection and require a gesture',
      () async {
    await seed();
    final id = service.profiles.first.id;
    expect(await service.select(id, directUserGesture: false), isFalse);
    await service.select(id, directUserGesture: true);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(service.active, isNull);
    expect(await service.select(id, directUserGesture: true), isFalse);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await service.select(id, directUserGesture: true);
    SafeBoot.instance.safeMode.value = true;
    expect(service.active, isNull);
    expect(await service.select(id, directUserGesture: true), isFalse);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = true;
    expect(await service.select(id, directUserGesture: true), isFalse);
    SafeBoot.instance.restartRequired.value = false;
    expect(service.active, isNull);
  });

  test('unconfirmed shutdown cannot activate another person', () async {
    await seed();
    final stopped = Completer<void>();
    final entered = Completer<void>();
    final blocked = LocalProfileService.forTesting(stopSession: () {
      if (!entered.isCompleted) entered.complete();
      return stopped.future;
    });
    addTearDown(blocked.dispose);
    final selection =
        blocked.select(service.profiles.first.id, directUserGesture: true);
    await entered.future;
    expect(blocked.active, isNull);
    stopped.completeError(StateError('synthetic microphone stop failure'));
    expect(await selection, isFalse);
    expect(blocked.active, isNull);
  });

  test('removal retains the other person and never reuses a removed identifier',
      () async {
    await seed();
    final alex = service.profiles.first;
    final blair = service.profiles.last;
    await service.select(alex.id, directUserGesture: true);
    expect(await service.remove(alex.id, directUserGesture: true), isTrue);
    expect(service.active, isNull);
    expect(service.profiles.single.id, blair.id);
    expect(await service.select(alex.id, directUserGesture: true), isFalse);
    expect(
        await service.create(
            label: 'Alex',
            persona: alex.persona,
            audience: alex.audience,
            directUserGesture: true),
        isTrue);
    expect(service.profiles.last.id, isNot(alex.id));
    await service.load();
    expect(service.profiles.first.persona.toMap(), blair.persona.toMap());
  });

  test('removing the final profile preserves the gate and existing ciphertext',
      () async {
    await fixture.seed('Synthetic retained installation memory');
    final preferences = Map.of(fixture.disk.preferences.data);
    final secrets = Map.of(fixture.disk.secrets);
    await seed();
    final removedIds = service.profiles.map((p) => p.id).toList();
    for (final id in removedIds) {
      expect(await service.remove(id, directUserGesture: true), isTrue);
    }
    expect(service.enabled, isTrue);
    expect(service.profiles, isEmpty);
    for (final entry in preferences.entries) {
      expect(fixture.disk.preferences.data[entry.key], entry.value);
    }
    expect(fixture.disk.secrets, secrets);
    final restarted = LocalProfileService.forTesting(stopSession: () async {});
    addTearDown(restarted.dispose);
    expect(await restarted.load(), isTrue);
    expect(restarted.enabled, isTrue);
    expect(restarted.profiles, isEmpty);
    expect(restarted.active, isNull);
    for (final id in removedIds) {
      expect(await restarted.select(id, directUserGesture: true), isFalse);
    }
    expect(await restarted.enable(directUserGesture: true), isFalse);
    expect(restarted.enabled, isTrue);
  });

  test('a false sentinel with missing ciphertext remains locked after restart',
      () async {
    await NeuraPrefsCache.prefs.setBool(LocalProfileService.modeKey, false);
    expect(await service.load(), isFalse);
    expect(service.enabled, isTrue);
    expect(service.active, isNull);
    expect(await service.enable(directUserGesture: true), isFalse);
    expect(await service.load(), isFalse);
    expect(service.enabled, isTrue);
    expect(NeuraPrefsCache.prefs.getBool(LocalProfileService.modeKey), isFalse);
    expect(NeuraPrefsCache.prefs.containsKey(LocalProfileService.storageKey),
        isFalse);
  });

  test(
      'corrupt or missing registry never falls back to installation preferences',
      () async {
    await seed();
    fixture.disk.preferences.data['flutter.${LocalProfileService.storageKey}'] =
        'not ciphertext';
    expect(await service.load(), isFalse);
    expect(service.enabled, isTrue);
    expect(service.active, isNull);
    fixture.disk.preferences.data
        .remove('flutter.${LocalProfileService.storageKey}');
    expect(await service.load(), isFalse);
    expect(
        await service.create(
            label: 'Replacement',
            persona: NeuraPersonaPreset.calm.profile,
            audience: NeuraAudience.adult,
            directUserGesture: true),
        isFalse);
    expect(service.active, isNull);
  });

  test('wipe drains an admitted delayed save and prevents resurrection',
      () async {
    await seed();
    final alex = service.profiles.first.id;
    await service.select(alex, directUserGesture: true);
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.disk.preferences.beforeSetValue = (key) async {
      if (key.endsWith(LocalProfileService.storageKey)) {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
    };
    final save = service.update(NeuraPersonaPreset.reflective.profile,
        expectedId: alex, expectedEpoch: service.epoch);
    await entered.future;
    var drained = false;
    final wipe = service.suspendForDataWipe().then((_) => drained = true);
    expect(service.active, isNull);
    expect(drained, isFalse);
    release.complete();
    expect(await save, isFalse);
    await wipe;
    fixture.disk.preferences.beforeSetValue = null;
    await NeuraPrefsCache.prefs.clear();
    await MemoryCrypto.clearDeviceKey();
    expect(await service.select(alex, directUserGesture: true), isFalse);
    expect(
        await service.create(
            label: 'Late',
            persona: NeuraPersonaPreset.calm.profile,
            audience: NeuraAudience.adult,
            directUserGesture: true),
        isFalse);
    expect(service.profiles, isEmpty);
    expect(NeuraPrefsCache.prefs.getString(LocalProfileService.storageKey),
        isNull);
    expect(fixture.disk.secrets['neura.memoryGraph.seed.v2'], isNull);
  });
}
