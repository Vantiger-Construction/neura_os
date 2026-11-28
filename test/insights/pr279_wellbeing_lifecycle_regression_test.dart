// These use production AES-GCM and the repository's isolated native fixture.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/insights/services/wellbeing_check_service.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DataWipeFixture disk;

  setUp(() async {
    disk = await DataWipeFixture.create();
    SafeBoot.instance.safeMode.value = false;
    await MemoryCrypto.clearDeviceKey();
    MemoryCrypto.resumeAfterDataWipe();
    addTearDown(() async {
      disk.preferences.beforeSetValue = null;
      await MemoryCrypto.clearDeviceKey();
      MemoryCrypto.resumeAfterDataWipe();
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
    });
  });

  test(
      'default wellbeing storage uses production authenticated encryption',
      () => disk.run(() async {
            final service = WellbeingCheckService();
            await service.record([5, 4, 3, 2, 1]);
            final blob = NeuraPrefsCache.prefs
                .getString(WellbeingCheckService.storageKey)!;
            final envelope = jsonDecode(blob) as Map<String, dynamic>;
            expect(envelope.keys, unorderedEquals(['n', 'c', 'm']));
            expect((await service.history()).single.percent, 60);
            expect(blob, isNot(contains('answers')));
            expect(
                NeuraPrefsCache.prefs.containsKey('neura.memoryGraph.seed.v1'),
                isFalse);
            final ciphertext = base64Decode(envelope['c'] as String);
            ciphertext[0] ^= 1;
            envelope['c'] = base64Encode(ciphertext);
            await NeuraPrefsCache.prefs.setString(
                WellbeingCheckService.storageKey, jsonEncode(envelope));
            await expectLater(service.history(), throwsA(isA<Exception>()));
            expect(disk.networkAttempts, 0);
            disk.expectIsolation();
          }));

  test(
      'profile revocation while encrypting prevents a write',
      () => disk.run(() async {
            var allowed = true;
            final entered = Completer<void>();
            final release = Completer<void>();
            final service = WellbeingCheckService(
                allowed: () => allowed,
                encrypt: (payload) async {
                  final blob =
                      await (await MemoryCrypto.demo()).encryptJson(payload);
                  entered.complete();
                  await release.future;
                  return blob;
                });
            final pending = service.record([2, 2, 2, 2, 2]);
            final rejected = expectLater(pending, throwsStateError);
            await entered.future;
            allowed = false;
            release.complete();
            await rejected;
            expect(
                NeuraPrefsCache.prefs
                    .containsKey(WellbeingCheckService.storageKey),
                isFalse);
            disk.expectIsolation();
          }));

  test(
      'profile revocation while decrypting does not return owner history',
      () => disk.run(() async {
            await WellbeingCheckService().record([2, 2, 2, 2, 2]);
            var allowed = true;
            final entered = Completer<void>();
            final release = Completer<void>();
            final service = WellbeingCheckService(
                allowed: () => allowed,
                decrypt: (blob) async {
                  final clear =
                      await (await MemoryCrypto.demo()).decryptJson(blob);
                  entered.complete();
                  await release.future;
                  return clear;
                });
            final pending = service.history();
            await entered.future;
            allowed = false;
            release.complete();
            expect(await pending, isEmpty);
            disk.expectIsolation();
          }));

  test(
      'a full wipe drains admitted wellbeing writes before preference clear',
      () => disk.run(() async {
            final entered = Completer<void>();
            final release = Completer<void>();
            disk.preferences.beforeSetValue = (key) async {
              if (key.endsWith(WellbeingCheckService.storageKey)) {
                entered.complete();
                await release.future;
              }
            };
            final pending = WellbeingCheckService().record([2, 2, 2, 2, 2]);
            final rejected = expectLater(pending, throwsStateError);
            await entered.future;
            final clearCalls = disk.preferences.clearCalls;
            final wiping = NeuraDataWipeService.wipeAllLocalData();
            await Future<void>.delayed(Duration.zero);
            expect(disk.preferences.clearCalls, clearCalls);
            release.complete();
            await rejected;
            await wiping;
            await NeuraPrefsCache.prefs.reload();
            expect(
                NeuraPrefsCache.prefs
                    .containsKey(WellbeingCheckService.storageKey),
                isFalse);
            expect(
                disk.preferences.data.keys.any(
                    (key) => key.endsWith(WellbeingCheckService.storageKey)),
                isFalse);
            expect(disk.networkAttempts, 0);
            disk.expectIsolation();
          }));

  test(
      'a new wellbeing service cannot bypass a started wipe',
      () => disk.run(() async {
            WellbeingCheckService.suspendAllForDataWipe();
            final service = WellbeingCheckService();
            expect(service.available, isFalse);
            await expectLater(
                service.record([1, 1, 1, 1, 1]), throwsStateError);
            expect(await service.history(), isEmpty);
            expect(disk.secrets, isEmpty);
            disk.expectIsolation();
          }));

  test(
      'new wellbeing saves reject an unverified legacy migration',
      () => disk.run(() async {
            final seed = base64UrlEncode(List<int>.filled(32, 7));
            await NeuraPrefsCache.prefs
                .setString('neura.memoryGraph.seed.v1', seed);
            disk.beforeSecretWrite =
                (_) async => throw StateError('Synthetic key write refusal');
            await expectLater(WellbeingCheckService().record([1, 1, 1, 1, 1]),
                throwsStateError);
            expect(
                NeuraPrefsCache.prefs
                    .containsKey(WellbeingCheckService.storageKey),
                isFalse);
            expect(NeuraPrefsCache.prefs.getString('neura.memoryGraph.seed.v1'),
                seed);
            disk.expectIsolation();
          }));

  test(
      'a stalled admitted write makes wipe incomplete before deletion',
      () => disk.run(() async {
            final entered = Completer<void>();
            final release = Completer<void>();
            addTearDown(() {
              if (!release.isCompleted) release.complete();
            });
            disk.preferences.beforeSetValue = (key) async {
              if (key.endsWith(WellbeingCheckService.storageKey)) {
                entered.complete();
                await release.future;
              }
            };
            final saving = WellbeingCheckService().record([2, 2, 2, 2, 2]);
            final rejected = expectLater(saving, throwsStateError);
            await entered.future;
            WellbeingCheckService.fullWipeDrainTimeout =
                const Duration(milliseconds: 20);
            final clears = disk.preferences.clearCalls;
            final keyDeletes = disk.deletedSecretKeys
                .where((key) => key == DataWipeFixture.memoryKey)
                .length;
            await expectLater(NeuraDataWipeService.wipeAllLocalData(),
                throwsA(isA<NeuraDataWipeException>()));
            expect(disk.preferences.clearCalls, clears);
            expect(
                disk.deletedSecretKeys
                    .where((key) => key == DataWipeFixture.memoryKey)
                    .length,
                keyDeletes);
            release.complete();
            await rejected;
            await NeuraDataWipeService.wipeAllLocalData();
            await NeuraPrefsCache.prefs.reload();
            expect(
                NeuraPrefsCache.prefs
                    .containsKey(WellbeingCheckService.storageKey),
                isFalse);
            disk.expectIsolation();
          }));
}
