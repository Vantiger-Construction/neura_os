import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/core/memory/memory_graph_service.dart';
import 'package:neuro_companion/core/neura_error_vault.dart';
import 'package:neuro_companion/core/neura_fault_event.dart';
import 'package:neuro_companion/modules/core/app_log.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_model_credentials.dart';
import 'package:neuro_companion/services/neura_model_types.dart';
import 'package:neuro_companion/services/neura_provider_credentials.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';
import 'package:neuro_companion/startup/neura_bootstrap_log.dart';

import 'helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Permanent writer/credential suspension is deliberately exercised in one
  // lifecycle. This file gets its own Flutter test isolate, like an app process.
  test(
      'late graph append cannot survive failed wipe, retry or repeated cleanup',
      () async {
    final f = await DataWipeFixture.create();
    final nodes = File('${f.documents.path}/neura_memory/nodes.jsonl');
    final paused = PausedWipeFile(nodes);
    f.pausedFile = paused;
    addTearDown(() {
      if (!paused.release.isCompleted) paused.release.complete();
    });
    await f.run(() async {
      await NeuraProviderCredentials.instance
          .save('sk-ant-synthetic-provider-credential-fixture');
      await NeuraModelCredentials.instance.save(
          NeuraModelProvider.openAi, 'sk-synthetic-model-credential-fixture');
      final crypto = await MemoryCrypto.demo();
      final oldCiphertext =
          await crypto.encryptJson({'text': 'synthetic private data'});
      await AppLog.instance.info('synthetic-before-wipe');
      await NeuraBootstrapLog.append({'source': 'synthetic-before-wipe'});
      final graph = MemoryGraphService.I;
      final write = graph.logUserAction(
          kind: 'synthetic', payload: {'text': 'synthetic private data'});
      // Attach the error handler before the paused writer can be invalidated.
      final writeOutcome = expectLater(write, throwsStateError);
      await paused.started.future.timeout(const Duration(seconds: 10));
      await expectLater(
        NeuraDataWipeService.wipeAllLocalData(),
        throwsA(isA<NeuraDataWipeException>().having((e) => e.failedSteps,
            'failed steps', contains('memory graph writer shutdown'))),
      );
      expect(SafeBoot.instance.safeMode.value, isTrue);
      expect(await nodes.parent.exists(), isFalse);
      expect(NeuraProviderCredentials.instance.apiKey, isEmpty);
      expect(NeuraModelCredentials.instance.configured.value, isEmpty);
      expect(f.secrets.containsKey(DataWipeFixture.memoryKey), isFalse);
      await expectLater(crypto.decryptJson(oldCiphertext), throwsStateError);
      await expectLater(
          graph.logUserAction(kind: 'late', payload: {'text': 'synthetic'}),
          throwsStateError);
      // A late OS append may transiently recreate a synthetic parent. The
      // real generation check must erase it and reject the stale operation.
      paused.release.complete();
      await writeOutcome;
      expect(await nodes.parent.exists(), isFalse);
      f.pausedFile = null;
      await NeuraDataWipeService.wipeAllLocalData();
      await NeuraDataWipeService.wipeAllLocalData();
      await AppLog.instance.info('synthetic-after-wipe');
      await NeuraBootstrapLog.append({'source': 'synthetic-after-wipe'});
      await NeuraErrorVault.append(
          NeuraFaultEvent(message: 'synthetic', source: 'test'));
      await expectLater(
          NeuraProviderCredentials.instance
              .save('sk-ant-synthetic-late-credential-fixture'),
          throwsStateError);
      await expectLater(
          NeuraModelCredentials.instance.save(NeuraModelProvider.openAi,
              'sk-synthetic-late-credential-fixture'),
          throwsStateError);
      expect(await nodes.parent.exists(), isFalse);
      expect(await Directory('${f.support.path}/neura').exists(), isFalse);
      expect(await File(f.bootstrapPath).exists(), isFalse);
      expect(
          await File('${f.systemTemporary.path}/neura_error_vault.jsonl')
              .exists(),
          isFalse);
      expect(f.secrets.containsKey(DataWipeFixture.providerKey), isFalse);
      expect(f.secrets.containsKey(DataWipeFixture.modelKey), isFalse);
      // A destroyed handle stays revoked after successful cleanup; only a
      // freshly loaded crypto authority may use a replacement device key.
      await expectLater(crypto.decryptJson(oldCiphertext), throwsStateError);
      f.expectIsolation();
    });
  }, timeout: const Timeout(Duration(seconds: 30)));
}
