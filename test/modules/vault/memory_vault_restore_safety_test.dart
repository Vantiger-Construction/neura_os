import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/vault/memory_vault_models.dart';
import 'package:neuro_companion/modules/vault/memory_vault_store.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../../helpers/data_wipe_fixture.dart';

VaultItem item(String id) => VaultItem(
    id: id,
    createdAt: DateTime.utc(2026, 1, 1),
    title: 'Synthetic $id',
    body: 'Synthetic body',
    tags: const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dataKey = 'neura.vault.data.v2';
  const seedKey = 'neura.vault.seed.secure.v2';
  late MemoryVaultStore store;
  late DataWipeFixture fixture;

  setUp(() async {
    fixture = await DataWipeFixture.create();
    store = MemoryVaultStore.forTesting();
  });

  test('restore refuses to replace unreadable existing ciphertext', () async {
    await store.configurePin('1234');
    final originalSecrets = Map.of(fixture.secrets);
    const damaged = '{"v":2,"cipher":"damaged"}';
    await NeuraPrefsCache.prefs.setString(dataKey, damaged);
    await expectLater(store.importItems(pin: '1234', imported: [item('new')]),
        throwsStateError);
    expect(NeuraPrefsCache.prefs.getString(dataKey), damaged);
    expect(fixture.secrets, originalSecrets);
  });

  test('wrong PIN and missing OS key never replace existing entries', () async {
    await store.configurePin('1234');
    await store.importItems(pin: '1234', imported: [item('existing')]);
    final original = NeuraPrefsCache.prefs.getString(dataKey);
    await expectLater(store.importItems(pin: '4321', imported: [item('new')]),
        throwsStateError);
    fixture.secrets.clear();
    await expectLater(store.importItems(pin: '1234', imported: [item('new')]),
        throwsStateError);
    expect(NeuraPrefsCache.prefs.getString(dataKey), original);
    expect(fixture.secrets, isEmpty);
  });

  test('malformed legacy data cannot migrate as an empty vault', () async {
    await store.configurePin('1234');
    const legacyKey = 'neura.vault.data.v1';
    final bytes = utf8.encode('{"not":"a list"}');
    final pin = utf8.encode('1234');
    final legacy = base64UrlEncode([
      for (var i = 0; i < bytes.length; i++) bytes[i] ^ pin[i % pin.length]
    ]);
    await NeuraPrefsCache.prefs.setString(legacyKey, legacy);
    await expectLater(store.importItems(pin: '1234', imported: [item('new')]),
        throwsFormatException);
    expect(NeuraPrefsCache.prefs.getString(legacyKey), legacy);
    expect(NeuraPrefsCache.prefs.containsKey(dataKey), false);
  });

  test('identical entries skip and conflicting versions preserve the original',
      () async {
    await store.configurePin('1234');
    final original = item('same');
    await store.importItems(pin: '1234', imported: [original]);
    final conflicting = VaultItem(
        id: original.id,
        createdAt: original.createdAt,
        title: 'Changed synthetic title',
        body: original.body,
        tags: original.tags);
    expect(
        await store.importItems(pin: '1234', imported: [original, conflicting]),
        1);
    final items = await store.getItems(pin: '1234');
    expect(
        items.map((e) => e.id), unorderedEquals(['same', 'same_recovered_1']));
    expect(items.firstWhere((e) => e.id == 'same').title, original.title);
  });

  test('revocation during encryption preparation prevents the final data write',
      () async {
    await store.configurePin('1234');
    await store.importItems(pin: '1234', imported: [item('existing')]);
    final original = NeuraPrefsCache.prefs.getString(dataKey);
    final entered = Completer<void>();
    final release = Completer<void>();
    var reads = 0;
    var allowed = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DataWipeFixture.secureChannel, (call) async {
      final key = (call.arguments as Map)['key'] as String;
      expect(call.method, 'read');
      if (++reads == 3) {
        // verifier, existing records, then encryption
        entered.complete();
        await release.future;
      }
      return fixture.secrets[key];
    });
    final restoring = store.importItems(
        pin: '1234', imported: [item('new')], mayWrite: () => allowed);
    final rejected = expectLater(restoring, throwsStateError);
    await entered.future;
    allowed = false;
    release.complete();
    await rejected;
    expect(NeuraPrefsCache.prefs.getString(dataKey), original);
  });

  test('full-data-wipe suspension rejects new and stale vault operations',
      () async {
    await store.configurePin('1234');
    final pending = store.importItems(pin: '1234', imported: [item('stale')]);
    final rejected = expectLater(pending, throwsStateError);
    store.suspendForDataWipe();
    await store.wipe();
    await rejected;
    await expectLater(store.importItems(pin: '1234', imported: [item('new')]),
        throwsStateError);
    await expectLater(store.configurePin('4321'), throwsStateError);
    expect(NeuraPrefsCache.prefs.containsKey(dataKey), false);
    expect(fixture.secrets, isEmpty);
  });

  test('wipe waits for a data write already admitted to platform storage',
      () async {
    await store.configurePin('1234');
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.preferences.beforeSetValue = (key) async {
      if (key == 'flutter.$dataKey') {
        entered.complete();
        await release.future;
      }
    };
    final restoring = store.importItems(pin: '1234', imported: [item('new')]);
    await entered.future;
    var wiped = false;
    final wiping = store.wipe().then((_) => wiped = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final completedBeforeDrain = wiped;
    release.complete();
    await Future.wait([restoring, wiping]);
    expect(completedBeforeDrain, false);
    expect(NeuraPrefsCache.prefs.containsKey(dataKey), false);
    expect(fixture.preferences.data.containsKey('flutter.$dataKey'), false);
    expect(fixture.secrets, isEmpty);
  });

  test('concurrent restores preserve both selected entries', () async {
    await store.configurePin('1234');
    await Future.wait([
      store.importItems(pin: '1234', imported: [item('one')]),
      store.importItems(pin: '1234', imported: [item('two')]),
    ]);
    expect((await store.getItems(pin: '1234')).map((e) => e.id),
        unorderedEquals(['one', 'two']));
  });

  test('wipe drains a restore blocked on an OS key read', () async {
    await store.configurePin('1234');
    await store.importItems(pin: '1234', imported: [item('existing')]);
    final entered = Completer<void>();
    final release = Completer<void>();
    var blocked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DataWipeFixture.secureChannel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      if (call.method == 'read' && key == seedKey && !blocked) {
        blocked = true;
        entered.complete();
        await release.future;
      }
      switch (call.method) {
        case 'read':
          return fixture.secrets[key];
        case 'write':
          fixture.secrets[key] = args['value'] as String;
          return null;
        case 'delete':
          fixture.secrets.remove(key);
          return null;
        default:
          throw PlatformException(code: 'UnexpectedMethod');
      }
    });
    final restoring = store.importItems(pin: '1234', imported: [item('new')]);
    // Attach before releasing asynchronous work so failures are observed.
    final observedRestore =
        restoring.then<void>((_) {}, onError: (Object _) {});
    await entered.future;
    var wiped = false;
    final wiping = store.wipe().then((_) => wiped = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final completedBeforeDrain = wiped;
    release.complete();
    await Future.wait([observedRestore, wiping]);
    expect(completedBeforeDrain, false);
    expect(NeuraPrefsCache.prefs.containsKey(dataKey), false);
    expect(fixture.secrets.containsKey(seedKey), false);
  });
}
