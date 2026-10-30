import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_durable_scoped_adapter.dart';
import 'package:neuro_companion/living_intelligence/neura_safety_policy.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/local_journal_store.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/companion_memory_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CompanionMemoryFixture f;
  final denied = throwsA(isA<EncryptedMemoryPolicyViolation>());
  setUp(() async => f = await CompanionMemoryFixture.create());

  test(
      'absent authorization denies recall and persistence before I/O',
      () => f.disk.run(() async {
            await expectLater(
                f.memory.recall(null, use: CompanionMemoryUse.review), denied);
            await expectLater(f.memory.remember(null, 'synthetic'), denied);
            expect(f.crypto.decryptions, 0);
            expect(f.crypto.encryptions, 0);
            expect(
                () => f.memory.authorize(CompanionMemoryUse.review,
                    directUserGesture: false),
                denied);
          }));

  test(
      'explicit note is encrypted, recall is single use, journal stays local',
      () => f.disk.run(() async {
            await LocalJournalStore().upsertEntry(
                id: 'synthetic-journal',
                content: 'Journal content never admitted');
            await f.seed();
            final raw = NeuraPrefsCache.prefs.getString(
                EncryptedMemoryDurableScopedAdapter.defaultStorageKey)!;
            expect(raw, isNot(contains('Synthetic companion note')));
            expect(raw, isNot(contains('Journal content')));
            final permission = f.grant(CompanionMemoryUse.review);
            final notes = await f.memory
                .recall(permission, use: CompanionMemoryUse.review);
            expect(notes.single.value, 'Synthetic companion note');
            expect(notes.single.provenance.requiresQuarantine, false);
            expect(notes.single.memoryClass,
                EncryptedMemoryClass.userAuthoredNote);
            await expectLater(
                f.memory.recall(permission, use: CompanionMemoryUse.review),
                denied);
            expect((await LocalJournalStore().loadEntries()).single.content,
                'Journal content never admitted');
          }));

  test(
      'scoped recall retains newest-first ordering and a bounded exact-scope tail',
      () => f.disk.run(() async {
            await f.seed('Older synthetic note');
            await f.seed('Newer synthetic note');
            final adapter = EncryptedMemoryDurableScopedAdapter(
                safetyPolicy: f.safety,
                keyLifecycle: f.keys,
                loadCrypto: () async => f.crypto,
                utcNow: () => f.now);
            await adapter.restore(
                safetyContext:
                    const NeuraSafetyContext(directUserGesture: true),
                expectedKeyGeneration: f.keys.generation);
            final permission = f.grant(CompanionMemoryUse.review);
            final result = adapter.recallScope(
                lease: permission.lease,
                safetyContext:
                    const NeuraSafetyContext(directUserGesture: true),
                scope: f.scope(),
                expectedKeyGeneration: f.keys.generation,
                nowUtc: f.now,
                limit: 1);
            expect(result.single.value, 'Newer synthetic note');
          }));

  for (final state in ['expired', 'revoked', 'before issue']) {
    test(
        '$state permission cannot restore/decrypt or persist',
        () => f.disk.run(() async {
              await f.seed();
              final recall = f.grant(CompanionMemoryUse.review);
              final remember = f.grant(CompanionMemoryUse.remember);
              if (state == 'expired') {
                f.now = f.now.add(const Duration(minutes: 5));
              }
              if (state == 'before issue') {
                f.now = f.now.subtract(const Duration(seconds: 1));
              }
              if (state == 'revoked') {
                recall.revoke();
                remember.revoke();
              }
              final before = f.crypto.decryptions;
              await expectLater(
                  f.memory.recall(recall, use: CompanionMemoryUse.review),
                  denied);
              await expectLater(
                  f.memory.remember(remember, 'Must not save'), denied);
              expect(f.crypto.decryptions, before);
              final fresh = f.grant(CompanionMemoryUse.review);
              final notes =
                  await f.memory.recall(fresh, use: CompanionMemoryUse.review);
              expect(notes.map((r) => r.value), ['Synthetic companion note']);
            }));
  }

  test(
      'review, prompt, write and foreign-owner permissions cannot substitute',
      () => f.disk.run(() async {
            await f.seed();
            final review = f.grant(CompanionMemoryUse.review);
            await expectLater(
                f.memory.recall(review, use: CompanionMemoryUse.prompt),
                denied);
            await expectLater(
                f.memory.remember(review, 'Must not save'), denied);
            for (final scope in [
              f.scope(owner: 'another-owner'),
              f.scope(device: 'another-device'),
              f.scope(capsule: 'another-capsule')
            ]) {
              final other = f.owner(
                  accessScope: scope,
                  storageKey:
                      'synthetic.${scope.ownerId}.${scope.deviceId}.${scope.capsuleId}');
              await expectLater(
                  other.recall(review, use: CompanionMemoryUse.review), denied);
            }
            expect(review.lease.isConsumed, false);
          }));

  test(
      'bounded scope lookup rejects every mismatched scope field',
      () => f.disk.run(() async {
            await f.seed();
            final adapter = EncryptedMemoryDurableScopedAdapter(
                safetyPolicy: f.safety,
                keyLifecycle: f.keys,
                loadCrypto: () async => f.crypto,
                utcNow: () => f.now);
            await adapter.restore(
                safetyContext:
                    const NeuraSafetyContext(directUserGesture: true),
                expectedKeyGeneration: f.keys.generation);
            for (final scope in [
              f.scope(owner: 'other'),
              f.scope(device: 'other'),
              f.scope(capsule: 'other'),
              f.scope(memoryClass: EncryptedMemoryClass.explicitPreference),
              f.scope(source: EncryptedMemorySource.modelOutput),
              f.scope(sensitivity: EncryptedMemorySensitivity.sensitive),
            ]) {
              final permission = f.grant(CompanionMemoryUse.review);
              expect(
                  () => adapter.recallScope(
                      lease: permission.lease,
                      safetyContext:
                          const NeuraSafetyContext(directUserGesture: true),
                      scope: scope,
                      expectedKeyGeneration: f.keys.generation,
                      nowUtc: f.now),
                  denied);
              expect(permission.lease.isConsumed, false);
            }
          }));

  test(
      'revocation during encryption prevents native persistence',
      () => f.disk.run(() async {
            f.crypto.pauseWrite = true;
            final permission = f.grant(CompanionMemoryUse.remember);
            final save = expectLater(
                f.memory.remember(permission, 'Revoked synthetic note'),
                denied);
            await f.crypto.entered.future;
            permission.revoke();
            f.crypto.release();
            await save;
            expect(
                NeuraPrefsCache.prefs.containsKey(
                    EncryptedMemoryDurableScopedAdapter.defaultStorageKey),
                false);
          }));

  test(
      'revocation after a native write was issued denies success until fresh reconciliation',
      () => f.disk.run(() async {
            await f.seed();
            final started = Completer<void>();
            final release = Completer<void>();
            f.disk.preferences.beforeSet = (key) async {
              if (key.endsWith(
                  EncryptedMemoryDurableScopedAdapter.defaultStorageKey)) {
                started.complete();
                await release.future;
              }
            };
            final permission = f.grant(CompanionMemoryUse.remember);
            final rejected = expectLater(
                f.memory.remember(permission, 'Synthetic native completion'),
                denied);
            await started.future;
            permission.revoke();
            release.complete();
            await rejected;
            f.disk.preferences.beforeSet = null;
            await expectLater(
                f.memory.recall(permission, use: CompanionMemoryUse.review),
                denied);
            final raw = NeuraPrefsCache.prefs.getString(
                EncryptedMemoryDurableScopedAdapter.defaultStorageKey)!;
            expect(raw, isNot(contains('Synthetic native completion')));
            final fresh = f.grant(CompanionMemoryUse.review);
            expect(
                (await f.memory.recall(fresh, use: CompanionMemoryUse.review))
                    .length,
                2);
          }));

  test(
      'expiry during cold restore suppresses recall',
      () => f.disk.run(() async {
            await f.seed();
            f.crypto.pauseRead = true;
            final permission = f.grant(CompanionMemoryUse.review);
            final result = expectLater(
                f.memory.recall(permission, use: CompanionMemoryUse.review),
                denied);
            await f.crypto.entered.future;
            f.now = f.now.add(const Duration(minutes: 5));
            f.crypto.release();
            await result;
            expect(permission.lease.isConsumed, false);
          }));

  test(
      'Safe Mode revokes old permissions, including after mode clears',
      () => f.disk.run(() async {
            await f.seed();
            final permission = f.grant(CompanionMemoryUse.review);
            SafeBoot.instance.safeMode.value = true;
            await expectLater(
                f.memory.recall(permission, use: CompanionMemoryUse.review),
                denied);
            SafeBoot.instance.safeMode.value = false;
            await expectLater(
                f.memory.recall(permission, use: CompanionMemoryUse.review),
                denied);
            expect(permission.lease.isRevoked, true);
          }));

  test(
      'background and recovery boundaries deny stale permissions',
      () => f.disk.run(() async {
            await f.seed();
            final permission = f.grant(CompanionMemoryUse.review);
            f.memory.didChangeAppLifecycleState(AppLifecycleState.paused);
            f.memory.didChangeAppLifecycleState(AppLifecycleState.resumed);
            await expectLater(
                f.memory.recall(permission, use: CompanionMemoryUse.review),
                denied);
            final fresh = f.grant(CompanionMemoryUse.review);
            f.recovery = true;
            await expectLater(
                f.memory.recall(fresh, use: CompanionMemoryUse.review), denied);
          }));

  test(
      'concurrent note saves cannot exceed the shared 100-record limit',
      () => f.disk.run(() async {
            for (var i = 0; i < 99; i++) {
              await f.seed('Synthetic note $i');
            }
            final other = f.owner();
            Future<bool> save(
                CompanionMemoryService owner, String value) async {
              final grant = owner.authorize(CompanionMemoryUse.remember,
                  directUserGesture: true);
              try {
                await owner.remember(grant, value);
                return true;
              } on EncryptedMemoryPolicyViolation {
                return false;
              } finally {
                grant.revoke();
              }
            }

            final results = await Future.wait([
              save(f.memory, 'First concurrent note'),
              save(other, 'Second concurrent note')
            ]);
            expect(results.where((ok) => ok).length, 1);
            final read = f.grant(CompanionMemoryUse.review);
            expect(
                (await f.memory.recall(read, use: CompanionMemoryUse.review))
                    .length,
                100);
          }));

  test(
      'scoped clear revokes prompt access and preserves local journals',
      () => f.disk.run(() async {
            await f.seed();
            await LocalJournalStore()
                .upsertEntry(id: 'journal', content: 'Keep local authority');
            final prompt = f.grant(CompanionMemoryUse.prompt);
            final wipe = f.grant(CompanionMemoryUse.wipe);
            await f.memory.wipeNotes(wipe);
            expect(prompt.lease.isRevoked, true);
            expect(
                NeuraPrefsCache.prefs.containsKey(
                    EncryptedMemoryDurableScopedAdapter.defaultStorageKey),
                false);
            final fresh = f.grant(CompanionMemoryUse.review);
            expect(await f.memory.recall(fresh, use: CompanionMemoryUse.review),
                isEmpty);
            expect((await LocalJournalStore().loadEntries()).single.content,
                'Keep local authority');
          }));
}
