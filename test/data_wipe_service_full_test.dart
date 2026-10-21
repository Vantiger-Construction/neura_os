import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/ambient_listening_prefs.dart';
import 'package:neuro_companion/services/ambient_listening_service.dart';
import 'package:neuro_companion/services/neura_provider_credentials.dart';
import 'package:neuro_companion/services/wake_word_listener_service.dart';
import 'package:neuro_companion/services/wake_word_prefs.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import 'helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> assertMicrophonesRemainOff() async {
    expect(SafeBoot.instance.safeMode.value, isTrue);
    expect(SafeBoot.instance.restartRequired.value, isTrue);
    expect(AmbientListeningPrefsController.instance.enabled.value, isFalse);
    expect(WakeWordPrefsController.instance.enabled.value, isFalse);
    expect(AmbientListeningService.instance.captureAllowed, isFalse);
    expect(WakeWordListenerService.instance.listeningAllowed, isFalse);
    await AmbientListeningService.instance.start();
    await WakeWordListenerService.instance.resume();
    await SafeBoot.instance.clearSafeMode();
    expect(SafeBoot.instance.safeMode.value, isTrue);
  }

  test(
      'full wipe removes exact owned targets and preserves neighbors in Safe Mode',
      () async {
    final f = await DataWipeFixture.create();
    await f.run(() async {
      SafeBoot.instance.safeMode.value = true;
      final owned = <File>[];
      for (final name in [
        'neura_memory',
        'neura_therapy',
        'neura_ambient_audio',
        'neura_legacy_vault'
      ]) {
        owned.add(await f.seed('${f.documents.path}/$name/private.json'));
      }
      owned.add(await f.seed('${f.documents.path}/sleep_123.m4a'));
      owned.add(await f.seed('${f.support.path}/neura/memory/private.enc'));
      owned.add(await f.seed(f.bootstrapPath));
      owned.add(await f.seed('${f.bootstrapPath}.old'));
      const tempNames = [
        'neura_error_vault.jsonl',
        'neura_error_vault.jsonl.1',
        'neura_error_vault.jsonl.2',
        'neura_error_vault.jsonl.3',
        'neura_bootstrap_export_2026-10-14T00-00-00.000Z.ndjson',
        'usage_entries_123.csv',
        'usage_report_123.pdf',
        'neura_weekly_snapshot_123.csv',
        'neura_weekly_snapshot_123.pdf',
        'neura_recap_123.pdf',
        'neura_legacy_vault_export_123.zip',
        'legacy_packet_fixture_123.zip',
        'legacy_fixture_123.pdf',
        'neura_life_timeline_fixture.json',
        'amb_playback_123.wav',
      ];
      for (final root in [f.temporary, f.systemTemporary]) {
        for (final name in tempNames) {
          owned.add(await f.seed('${root.path}/$name'));
        }
      }
      final neighbors = <File>[];
      for (final name in [
        'neura_memory_backup/keep.txt',
        'neura_legacy_vault_backup/keep.txt',
        'sleep_notes.m4a',
        'sleep_123.m4a.bak',
        'neighbor/sleep_123.m4a'
      ]) {
        neighbors.add(await f.seed('${f.documents.path}/$name', 'keep'));
      }
      neighbors
          .add(await f.seed('${f.support.path}/neura_backup/keep.txt', 'keep'));
      for (final root in [f.temporary, f.systemTemporary]) {
        for (final name in [
          'neura_error_vault.jsonl.4',
          'usage_entries_notes.csv',
          'xusage_report_123.pdf',
          'amb_playback_123.wav.bak',
          'neighbor/usage_report_123.pdf'
        ]) {
          neighbors.add(await f.seed('${root.path}/$name', 'keep'));
        }
      }
      // A link named as an owned directory must be unlinked, never followed.
      final linkedNeighbor =
          await f.seed('${f.root.path}/neighbor-vault/keep.txt', 'keep');
      final vault = Directory('${f.documents.path}/neura_legacy_vault');
      await vault.delete(recursive: true);
      await Link(vault.path).create(linkedNeighbor.parent.path);
      owned.removeWhere((file) => file.path.startsWith('${vault.path}/'));
      neighbors.add(linkedNeighbor);
      await NeuraPrefsCache.prefs
          .setString('private_journal_fixture', 'synthetic');
      f.secrets.addAll({
        DataWipeFixture.providerKey: 'synthetic-provider-secret',
        DataWipeFixture.modelKey: 'synthetic-model-secret',
        DataWipeFixture.backupKey: 'synthetic-backup-secret',
        'unrelated-fixture-secret': 'keep',
      });
      await NeuraDataWipeService.wipeAllLocalData();
      for (final file in owned) {
        expect(await file.exists(), isFalse, reason: file.path);
      }
      expect(await Link(vault.path).exists(), isFalse);
      for (final file in neighbors) {
        expect(await file.readAsString(), 'keep', reason: file.path);
      }
      expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
      expect(f.preferences.data, isEmpty);
      expect(f.secrets, {
        'unrelated-fixture-secret': 'keep',
        DataWipeFixture.tombstoneKey: 'disabled',
      });
      await assertMicrophonesRemainOff();
      await NeuraDataWipeService.wipeAllLocalData();
      for (final file in owned) {
        expect(await file.exists(), isFalse);
      }
      f.expectIsolation();
    });
  });

  for (final failure in ['false', 'throw', 'ignored']) {
    test('preference clear $failure is incomplete even if its cache is empty',
        () async {
      final f = await DataWipeFixture.create();
      await f.run(() async {
        await NeuraPrefsCache.prefs
            .setString('private_journal_fixture', 'synthetic');
        final target =
            await f.seed('${f.documents.path}/neura_therapy/private.json');
        f.preferences.refuseClear = failure == 'false';
        f.preferences.throwOnClear = failure == 'throw';
        f.preferences.ignoreClear = failure == 'ignored';
        await expectLater(
          NeuraDataWipeService.wipeAllLocalData(),
          throwsA(isA<NeuraDataWipeException>().having((e) => e.failedSteps,
              'failed steps', contains('preferences deletion'))),
        );
        expect(f.preferences.data, contains('flutter.private_journal_fixture'));
        expect(await target.exists(), isFalse);
        await expectLater(MemoryCrypto.demo(), throwsStateError);
        await assertMicrophonesRemainOff();
        f.preferences.refuseClear = false;
        f.preferences.throwOnClear = false;
        f.preferences.ignoreClear = false;
        await NeuraDataWipeService.wipeAllLocalData();
        expect(f.preferences.data, isEmpty);
        expect(await target.exists(), isFalse);
        f.expectIsolation();
      });
    });
  }

  test('multiple cleanup failures are redacted, independent and retryable',
      () async {
    final f = await DataWipeFixture.create();
    await f.run(() async {
      final blocked =
          await f.seed('${f.documents.path}/neura_therapy/private.json');
      final removed =
          await f.seed('${f.documents.path}/neura_legacy_vault/private.json');
      final temporary =
          await f.seed('${f.systemTemporary.path}/usage_report_123.pdf');
      f.blockedPaths.add(blocked.parent.path);
      f.thrownSecretDeletes.add(DataWipeFixture.memoryKey);
      f.failedTemporaryLookup = 'synthetic secret path and transcript';
      NeuraDataWipeException? failure;
      try {
        await NeuraDataWipeService.wipeAllLocalData();
      } on NeuraDataWipeException catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      expect(
          failure!.failedSteps,
          containsAll([
            'device encryption key deletion',
            'neura_therapy deletion',
            'temporary directory lookup'
          ]));
      expect(failure.toString(), isNot(contains('transcript')));
      expect(failure.toString(), isNot(contains(f.root.path)));
      expect(() => failure!.failedSteps.add('other'), throwsUnsupportedError);
      expect(await blocked.exists(), isTrue);
      expect(await removed.exists(), isFalse);
      expect(await temporary.exists(), isFalse);
      expect(
          f.deletedSecretKeys,
          containsAll([
            DataWipeFixture.providerKey,
            DataWipeFixture.modelKey,
            DataWipeFixture.backupKey
          ]));
      await assertMicrophonesRemainOff();
      f.blockedPaths.clear();
      f.thrownSecretDeletes.clear();
      f.failedTemporaryLookup = null;
      await NeuraDataWipeService.wipeAllLocalData();
      expect(await blocked.exists(), isFalse);
      f.expectIsolation();
    });
  });

  test('interrupted key deletion keeps wipe pending and gates closed',
      () async {
    final f = await DataWipeFixture.create();
    await f.run(() async {
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      f.beforeSecretDelete = (key) async {
        if (key != DataWipeFixture.memoryKey) return;
        entered.complete();
        await release.future;
        throw StateError('synthetic interrupted key removal');
      };
      final target = await f.seed('${f.support.path}/neura/private.enc');
      var completed = false;
      final wipe = NeuraDataWipeService.wipeAllLocalData();
      final outcome = expectLater(wipe, throwsA(isA<NeuraDataWipeException>()))
          .whenComplete(() => completed = true);
      await entered.future.timeout(const Duration(seconds: 10));
      expect(completed, isFalse);
      expect(await target.exists(), isTrue);
      expect(SafeBoot.instance.safeMode.value, isTrue);
      expect(AmbientListeningPrefsController.instance.enabled.value, isFalse);
      expect(WakeWordPrefsController.instance.enabled.value, isFalse);
      await expectLater(MemoryCrypto.demo(), throwsStateError);
      release.complete();
      await outcome;
      expect(await target.exists(), isFalse);
      expect(NeuraProviderCredentials.instance.apiKey, isEmpty);
      f.beforeSecretDelete = null;
      await NeuraDataWipeService.wipeAllLocalData();
      await assertMicrophonesRemainOff();
      f.expectIsolation();
    });
  });

  test('failed documents lookup still clears other roots and can be retried',
      () async {
    final f = await DataWipeFixture.create();
    await f.run(() async {
      final documents =
          await f.seed('${f.documents.path}/neura_memory/private.json');
      final support = await f.seed('${f.support.path}/neura/private.enc');
      f.failedDocumentsLookup = 'synthetic unavailable documents';
      await expectLater(NeuraDataWipeService.wipeAllLocalData(),
          throwsA(isA<NeuraDataWipeException>()));
      expect(await documents.exists(), isTrue);
      expect(await support.exists(), isFalse);
      f.failedDocumentsLookup = null;
      await NeuraDataWipeService.wipeAllLocalData();
      expect(await documents.exists(), isFalse);
      f.expectIsolation();
    });
  });

  for (final entry in {
    DataWipeFixture.memoryKey: 'device encryption key deletion',
    DataWipeFixture.modelKey: 'model credential deletion',
    DataWipeFixture.backupKey: 'scheduled backup settings deletion',
  }.entries) {
    test('ignored ${entry.value} cannot report success', () async {
      final f = await DataWipeFixture.create();
      await f.run(() async {
        f.secrets[entry.key] = 'synthetic-undeleted-secret';
        f.ignoredSecretDeletes.add(entry.key);
        final target = await f.seed('${f.support.path}/neura/private.enc');
        await expectLater(
          NeuraDataWipeService.wipeAllLocalData(),
          throwsA(isA<NeuraDataWipeException>().having(
              (e) => e.failedSteps, 'failed steps', contains(entry.value))),
        );
        expect(await target.exists(), isFalse);
        expect(f.secrets[entry.key], 'synthetic-undeleted-secret');
        await assertMicrophonesRemainOff();
        f.ignoredSecretDeletes.clear();
        await NeuraDataWipeService.wipeAllLocalData();
        expect(f.secrets.containsKey(entry.key), isFalse);
        f.expectIsolation();
      });
    });
  }
}
