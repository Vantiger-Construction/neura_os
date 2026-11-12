import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/profiles/local_profile_service.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/teaching/neura_teaching_preferences.dart';
import 'package:neuro_companion/teaching/neura_teaching_service.dart';

import '../helpers/companion_memory_fixture.dart';

class _Store implements NeuraTeachingStore {
  NeuraTeachingPreferences value = const NeuraTeachingPreferences();
  @override
  bool authorityCurrent = true;
  int writes = 0;
  bool fail = false;
  bool commitThenFail = false;
  Completer<void>? beforeRead;
  Completer<void>? beforeSubmit;
  Completer<void>? afterSubmit;
  final submitted = Completer<void>();

  @override
  Future<NeuraTeachingPreferences> read(
      {required bool Function() stillAllowed}) async {
    await beforeRead?.future;
    return value;
  }

  @override
  Future<void> write(NeuraTeachingPreferences next,
      {required bool Function() stillAllowed}) async {
    await beforeSubmit?.future;
    if (!stillAllowed()) throw StateError('Revoked before submission');
    writes++;
    if (!submitted.isCompleted) submitted.complete();
    await afterSubmit?.future;
    if (fail) throw StateError('Synthetic failure');
    value = next;
    if (commitThenFail) throw StateError('Synthetic ambiguous commit');
  }
}

NeuraTeachingService _owner(NeuraTeachingStore store,
    {DateTime Function()? now, bool Function()? profileMode}) {
  final service = NeuraTeachingService.forTesting(
      store: store, now: now, profileMode: profileMode ?? () => false);
  addTearDown(service.dispose);
  return service;
}

NeuraTeachingPermit _permit(NeuraTeachingService service) =>
    service.beginChange(directUserGesture: true);

Future<void> _brief(NeuraTeachingService service, {bool today = false}) =>
    service.setAnswerDetail(_permit(service), NeuraAnswerDetail.brief,
        today: today);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraTeachingService.resetWipeGateForTesting();
  });
  tearDown(() async {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    await NeuraTeachingService.drainAllForDataWipe();
    NeuraTeachingService.resetWipeGateForTesting();
  });

  test('independent saves, replacement, removal and restart', () async {
    final store = _Store();
    final service = _owner(store);
    await service.load();
    await _brief(service);
    await service.setPlanSize(_permit(service), NeuraPlanSize.one,
        today: false);
    await service.setAnswerDetail(_permit(service), NeuraAnswerDetail.detailed,
        today: false);
    expect(service.saved.planSize, NeuraPlanSize.one);
    final restarted = _owner(store);
    await restarted.load();
    expect(restarted.saved.answerDetail, NeuraAnswerDetail.detailed);
    expect(restarted.saved.planSize, NeuraPlanSize.one);
    await restarted.removeAnswerDetail(_permit(restarted));
    expect(restarted.saved.answerDetail, isNull);
    expect(restarted.saved.planSize, NeuraPlanSize.one);
    await restarted.removePlanSize(_permit(restarted));
    expect(store.value.isEmpty, isTrue);
  });

  test('today does not persist and local day change restores saved value',
      () async {
    var now = DateTime(2026, 11, 12, 23, 59);
    final store = _Store();
    final service = _owner(store, now: () => now);
    await service.load();
    await _brief(service);
    await service.setAnswerDetail(_permit(service), NeuraAnswerDetail.detailed,
        today: true);
    await service.setPlanSize(_permit(service), NeuraPlanSize.one, today: true);
    expect(store.writes, 1);
    expect(service.current.answerDetail, NeuraAnswerDetail.detailed);
    final restarted = _owner(store);
    await restarted.load();
    expect(restarted.current.answerDetail, NeuraAnswerDetail.brief);
    expect(restarted.current.planSize, isNull);
    final midnightPermit = _permit(service);
    now = DateTime(2026, 11, 13);
    expect(service.answerIsTemporary, isFalse);
    expect(service.current.answerDetail, NeuraAnswerDetail.brief);
    expect(service.current.planSize, isNull);
    await expectLater(
        service.setPlanSize(midnightPermit, NeuraPlanSize.three, today: true),
        throwsStateError);
  });

  test('requires loaded state, gesture, owner and a fresh unused permit',
      () async {
    var now = DateTime(2026, 11, 12, 12);
    final store = _Store();
    final service = _owner(store, now: () => now);
    expect(() => _permit(service), throwsStateError);
    await service.load();
    expect(
        () => service.beginChange(directUserGesture: false), throwsStateError);
    final other = _owner(_Store());
    await other.load();
    await expectLater(
        service.setAnswerDetail(_permit(other), NeuraAnswerDetail.brief,
            today: false),
        throwsStateError);
    final revoked = _permit(service)..revoke();
    await expectLater(
        service.setAnswerDetail(revoked, NeuraAnswerDetail.brief, today: false),
        throwsStateError);
    final expired = _permit(service);
    now = now.add(const Duration(minutes: 5));
    await expectLater(
        service.setAnswerDetail(expired, NeuraAnswerDetail.brief, today: false),
        throwsStateError);
    final backward = _permit(service);
    now = now.subtract(const Duration(seconds: 1));
    await expectLater(
        service.setAnswerDetail(backward, NeuraAnswerDetail.brief,
            today: false),
        throwsStateError);
    final used = _permit(service);
    await service.setAnswerDetail(used, NeuraAnswerDetail.brief, today: false);
    await expectLater(
        service.setAnswerDetail(used, NeuraAnswerDetail.detailed, today: false),
        throwsStateError);
    expect(store.writes, 1);
  });

  test('overlap is rejected and pre-submission revocation prevents write',
      () async {
    final store = _Store()..beforeSubmit = Completer<void>();
    final service = _owner(store);
    await service.load();
    final first = _permit(service);
    final second = _permit(service);
    final pending =
        service.setAnswerDetail(first, NeuraAnswerDetail.brief, today: false);
    final rejected = expectLater(pending, throwsStateError);
    expect(service.busy, isTrue);
    expect(() => _permit(service), throwsStateError);
    await expectLater(
        service.setPlanSize(second, NeuraPlanSize.one, today: false),
        throwsStateError);
    first.revoke();
    store.beforeSubmit!.complete();
    await rejected;
    expect(store.writes, 0);
    expect(service.loaded, isFalse);
  });

  for (final boundary in ['background', 'safe', 'recovery', 'profile']) {
    test('$boundary revokes loaded data, temporary values and pending permits',
        () async {
      var profile = false;
      final store = _Store();
      final service = _owner(store, profileMode: () => profile);
      await service.load();
      await _brief(service);
      await service.setPlanSize(_permit(service), NeuraPlanSize.one,
          today: true);
      final pending = _permit(service);
      switch (boundary) {
        case 'background':
          service.didChangeAppLifecycleState(AppLifecycleState.paused);
          break;
        case 'safe':
          SafeBoot.instance.safeMode.value = true;
          break;
        case 'recovery':
          SafeBoot.instance.restartRequired.value = true;
          break;
        case 'profile':
          profile = true;
          // Paused enable notifies listeners without enabling real profiles.
          await LocalProfileService.instance.enable(directUserGesture: true);
          break;
      }
      expect(service.available, isFalse);
      expect(service.saved.isEmpty, isTrue);
      expect(service.current.isEmpty, isTrue);
      await expectLater(
          service.setAnswerDetail(pending, NeuraAnswerDetail.detailed,
              today: false),
          throwsStateError);
      profile = false;
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.loaded, isFalse);
      await service.load();
      expect(service.current.answerDetail, NeuraAnswerDetail.brief);
      expect(service.current.planSize, isNull);
    });
  }

  for (final committed in [false, true]) {
    test('failed commit ($committed) requires durable review, never retries',
        () async {
      final store = _Store()
        ..fail = !committed
        ..commitThenFail = committed;
      final service = _owner(store);
      await service.load();
      await expectLater(_brief(service), throwsStateError);
      expect(service.loaded, isFalse);
      expect(service.current.isEmpty, isTrue);
      expect(service.error, isNotNull);
      expect(() => _permit(service), throwsStateError);
      store.fail = false;
      store.commitThenFail = false;
      await service.load();
      expect(service.saved.answerDetail,
          committed ? NeuraAnswerDetail.brief : null);
      expect(store.writes, 1);
    });
  }

  test('late read after background cannot restore a decrypted cache', () async {
    final store = _Store()
      ..value =
          const NeuraTeachingPreferences(answerDetail: NeuraAnswerDetail.brief)
      ..beforeRead = Completer<void>();
    final service = _owner(store);
    final load = service.load();
    final rejected = expectLater(load, throwsStateError);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    store.beforeRead!.complete();
    await rejected;
    expect(service.loaded, isFalse);
    expect(service.current.isEmpty, isTrue);
    await service.load();
    expect(service.saved.answerDetail, NeuraAnswerDetail.brief);
  });

  test('wipe drain stays pending until an admitted write actually settles',
      () async {
    final store = _Store()..afterSubmit = Completer<void>();
    final service = _owner(store);
    await service.load();
    final rejected = expectLater(_brief(service), throwsStateError);
    await store.submitted.future;
    NeuraTeachingService.suspendAllForDataWipe();
    var drained = false;
    final drain = NeuraTeachingService.drainAllForDataWipe().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    store.afterSubmit!.complete();
    await rejected;
    await drain;
    expect(drained, isTrue);
    expect(service.current.isEmpty, isTrue);
  });

  test(
      'wipe drains submitted writes, times out closed and suppresses late cache',
      () async {
    final store = _Store()..afterSubmit = Completer<void>();
    final service = _owner(store);
    await service.load();
    final write = _brief(service);
    final rejected = expectLater(write, throwsStateError);
    await store.submitted.future;
    NeuraTeachingService.suspendAllForDataWipe();
    expect(service.available, isFalse);
    NeuraTeachingService.wipeDrainTimeout = const Duration(milliseconds: 10);
    await expectLater(NeuraTeachingService.drainAllForDataWipe(),
        throwsA(isA<TimeoutException>()));
    expect(
        () => NeuraTeachingService.resetWipeGateForTesting(), throwsStateError);
    store.afterSubmit!.complete();
    await rejected;
    await NeuraTeachingService.drainAllForDataWipe();
    expect(store.value.answerDetail, NeuraAnswerDetail.brief);
    expect(service.current.isEmpty, isTrue);
    expect(service.available, isFalse);
  });

  group('real encrypted store with isolated synthetic platform', () {
    const key = NeuraEncryptedTeachingStore.storageKey;
    const diskKey = 'flutter.$key';

    test('absence, encrypted persistence, restart, removal and key revocation',
        () async {
      final fixture = await CompanionMemoryFixture.create();
      await fixture.disk.run(() async {
        final service = _owner(NeuraEncryptedTeachingStore());
        await service.load();
        expect(service.saved.isEmpty, isTrue);
        expect(fixture.disk.preferences.data.containsKey(diskKey), isFalse);
        await _brief(service);
        final raw = fixture.disk.preferences.data[diskKey] as String;
        expect(raw, isNot(contains('answer_detail')));
        expect(raw, isNot(contains('brief')));
        final restarted = _owner(NeuraEncryptedTeachingStore());
        await restarted.load();
        expect(restarted.saved.answerDetail, NeuraAnswerDetail.brief);
        await restarted.removeAnswerDetail(_permit(restarted));
        expect(fixture.disk.preferences.data.containsKey(diskKey), isFalse);
        await _brief(restarted);
        await MemoryCrypto.clearDeviceKey();
        expect(restarted.loaded, isFalse);
        expect(restarted.current.isEmpty, isTrue);
        expect(() => _permit(restarted), throwsStateError);
        await expectLater(restarted.load(), throwsStateError);
        fixture.disk.expectIsolation();
      });
    });

    for (final malformed in [
      'empty',
      'corrupt',
      'oversized',
      'type',
      'schema'
    ]) {
      test('$malformed stored record blocks edits without overwriting data',
          () async {
        final fixture = await CompanionMemoryFixture.create();
        await fixture.disk.run(() async {
          final Object raw;
          switch (malformed) {
            case 'empty':
              raw = '';
              break;
            case 'corrupt':
              raw = '{broken envelope';
              break;
            case 'oversized':
              raw = List.filled(4097, 'x').join();
              break;
            case 'type':
              raw = 42;
              break;
            default:
              raw = await (await MemoryCrypto.demo()).encryptJson({
                'version': 1,
                'answer_detail': 'inferred',
                'plan_size': null,
              });
          }
          fixture.disk.preferences.data[diskKey] = raw;
          final service = _owner(NeuraEncryptedTeachingStore());
          await expectLater(service.load(), throwsA(anything));
          expect(service.loaded, isFalse);
          expect(service.current.isEmpty, isTrue);
          expect(() => _permit(service), throwsStateError);
          expect(fixture.disk.preferences.data[diskKey], raw);
          fixture.disk.expectIsolation();
        });
      });
    }

    for (final failure in ['refused', 'committed-false', 'readback']) {
      test('$failure platform save is unconfirmed until reloaded', () async {
        final fixture = await CompanionMemoryFixture.create();
        await fixture.disk.run(() async {
          final service = _owner(NeuraEncryptedTeachingStore());
          await service.load();
          if (failure == 'refused') {
            fixture.disk.preferences.refusedWrites.add(diskKey);
          } else if (failure == 'committed-false') {
            fixture.disk.preferences.misreportedWrites.add(diskKey);
          } else {
            fixture.disk.preferences.beforeGetAll = () async {
              fixture.disk.preferences.data.remove(diskKey);
            };
          }
          await expectLater(_brief(service), throwsStateError);
          expect(service.loaded, isFalse);
          expect(service.saved.isEmpty, isTrue);
          fixture.disk.preferences.refusedWrites.clear();
          fixture.disk.preferences.misreportedWrites.clear();
          fixture.disk.preferences.beforeGetAll = null;
          await service.load();
          expect(service.saved.answerDetail,
              failure == 'committed-false' ? NeuraAnswerDetail.brief : null);
          fixture.disk.expectIsolation();
        });
      });
    }

    for (final refused in [true, false]) {
      test('platform removal refusal=$refused never reports removed', () async {
        final fixture = await CompanionMemoryFixture.create();
        await fixture.disk.run(() async {
          final service = _owner(NeuraEncryptedTeachingStore());
          await service.load();
          await _brief(service);
          final failures = refused
              ? fixture.disk.preferences.refusedRemovals
              : fixture.disk.preferences.ignoredRemovals;
          failures.add(diskKey);
          await expectLater(
              service.removeAnswerDetail(_permit(service)), throwsStateError);
          expect(service.loaded, isFalse);
          failures.clear();
          await service.load();
          expect(service.saved.answerDetail, NeuraAnswerDetail.brief);
          await service.removeAnswerDetail(_permit(service));
          await NeuraPrefsCache.prefs.reload();
          expect(NeuraPrefsCache.prefs.containsKey(key), isFalse);
          fixture.disk.expectIsolation();
        });
      });
    }
  });
}
