import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:neuro_companion/constitution/neura_constitution_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    await NeuraPrefsCache.prefs.remove('neura.constitution.v1');
    await NeuraPrefsCache.prefs.remove('neura.adaptive_intent.state.v1');
    NeuraConstitutionService.instance.resetAfterDataWipe();
  });

  test('current is the default constitution before anything is saved', () {
    final current = NeuraConstitutionService.instance.current;
    expect(current.allowCloudAi, isTrue);
    expect(current.allowExternalMessages, isFalse);
  });

  test('save persists and is reflected immediately, without an explicit load',
      () async {
    final service = NeuraConstitutionService.instance;
    await service.save(
      service.current.copyWith(allowExternalMessages: true),
    );

    expect(service.current.allowExternalMessages, isTrue);
  });

  test('load restores a previously saved constitution', () async {
    final service = NeuraConstitutionService.instance;
    await service.save(
      service.current.copyWith(allowPurchases: true, workHoursStart: 9),
    );

    service.resetAfterDataWipe();
    expect(service.current.allowPurchases, isFalse); // back to default

    await service.load();
    expect(service.current.allowPurchases, isTrue);
    expect(service.current.workHoursStart, 9);
  });

  test('load migrates an explicit Adaptive Intent cloud boundary', () async {
    await NeuraPrefsCache.prefs.setString(
      'neura.adaptive_intent.state.v1',
      jsonEncode({
        'v': 1,
        'saved_at': '2026-01-01T00:00:00.000Z',
        'signals': <String, Object?>{},
        'constitution': {
          'allow_cloud_ai': false,
          'allow_external_messages': false,
          'keep_sensitive_content_local': true,
        },
      }),
    );

    final service = NeuraConstitutionService.instance;
    await service.load();

    expect(service.current.allowCloudAi, isFalse);
    expect(
      NeuraPrefsCache.prefs.getString('neura.constitution.v1'),
      isNotNull,
    );
  });

  test('corrupt persisted policy fails closed for cloud AI', () async {
    await NeuraPrefsCache.prefs.setString(
      'neura.constitution.v1',
      '{not-valid-json',
    );

    final service = NeuraConstitutionService.instance;
    await service.load();

    expect(service.current.allowCloudAi, isFalse);
  });

  test('resetAfterDataWipe forgets the in-memory constitution', () async {
    final service = NeuraConstitutionService.instance;
    await service.save(service.current.copyWith(allowCloudAi: false));
    expect(service.current.allowCloudAi, isFalse);

    service.resetAfterDataWipe();

    expect(service.current.allowCloudAi, isTrue); // back to default
  });

  test('save revokes approvals synchronously before persistence finishes',
      () async {
    final service = NeuraConstitutionService.instance;
    final previousStore = SharedPreferencesStorePlatform.instance;
    final store = _DelayedPolicyStore();
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
      SharedPreferencesStorePlatform.instance = previousStore;
    });
    final before = service.revision.value;
    final observed = <bool>[];
    void changed() => observed.add(service.current.allowExternalMessages);
    service.revision.addListener(changed);
    addTearDown(() => service.revision.removeListener(changed));
    var finished = false;
    final saving = service
        .save(service.current.copyWith(allowExternalMessages: true))
        .then((_) => finished = true);
    expect(service.revision.value, before + 1);
    expect(observed, [true]);
    await store.entered.future;
    expect(finished, false);
    store.release.complete();
    await saving;
    expect(service.revision.value, before + 1);
  });

  test('revoke, restore and repeated saves each have a new revision', () async {
    final service = NeuraConstitutionService.instance;
    final before = service.revision.value;
    await service.save(service.current.copyWith(allowExternalMessages: true));
    await service.save(service.current.copyWith(allowExternalMessages: false));
    await service.save(service.current.copyWith(allowExternalMessages: true));
    await service.save(service.current);
    expect(service.revision.value, before + 4);
  });

  test('wipe reset synchronously invalidates policy approvals', () async {
    final service = NeuraConstitutionService.instance;
    await service.save(service.current.copyWith(allowExternalMessages: true));
    final before = service.revision.value;
    var notifications = 0;
    void changed() {
      notifications++;
      expect(service.current.allowExternalMessages, false);
    }

    service.revision.addListener(changed);
    try {
      service.resetAfterDataWipe();
      expect(service.revision.value, before + 1);
      expect(notifications, 1);
    } finally {
      service.revision.removeListener(changed);
    }
  });
}

class _DelayedPolicyStore extends SharedPreferencesStorePlatform {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  bool get isMock => true;

  @override
  Future<Map<String, Object>> getAll() async => {};

  @override
  Future<bool> remove(String key) async => true;

  @override
  Future<bool> clear() async => true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    entered.complete();
    await release.future;
    return true;
  }
}
