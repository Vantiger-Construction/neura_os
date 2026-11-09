import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/vault/memory_vault_models.dart';
import 'package:neuro_companion/modules/vault/memory_vault_store.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../../helpers/data_wipe_fixture.dart';

const _data = 'neura.vault.data.v2';
const _oldData = 'neura.vault.data.v1';
const _oldPin = 'neura.vault.pin.v1';
const _verifier = 'neura.vault.pinVerifier.v1';
const _oldSeed = 'neura.vault.seed.v1';
const _seed = 'neura.vault.seed.secure.v2';
const _marker = 'neura.vault.seed.secure.marker.v2';

VaultItem _item(String id, [String title = 'Synthetic']) => VaultItem(
      id: id,
      createdAt: DateTime.utc(2026),
      title: title,
      body: 'Synthetic body',
      tags: const [],
    );

String _legacy(List<VaultItem> items) {
  final bytes = utf8.encode(encodeVaultItems(items));
  final pin = utf8.encode('1234');
  return base64UrlEncode(
    List.generate(bytes.length, (i) => bytes[i] ^ pin[i % pin.length]),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DataWipeFixture fixture;
  late MemoryVaultStore store;

  setUp(() async {
    fixture = await DataWipeFixture.create();
    store = MemoryVaultStore.forTesting();
  });

  Future<void> seedCurrent() async {
    await store.configurePin('1234');
    await store.importItems(
      pin: '1234',
      imported: [_item('original')],
      mayWrite: () => true,
    );
  }

  for (final marked in [false, true]) {
    test(
      'conflicting seed copies preserve both keys (marker: $marked)',
      () async {
        await seedCurrent();
        await NeuraPrefsCache.prefs.setString(
          _oldSeed,
          base64UrlEncode(List<int>.filled(32, 7)),
        );
        await NeuraPrefsCache.prefs.setBool(_marker, marked);
        final original = Map.of(fixture.preferences.data);
        final secrets = Map.of(fixture.secrets);
        store = MemoryVaultStore.forTesting();
        expect(await store.validatePin('1234'), isFalse);
        await expectLater(store.getItems(pin: '1234'), throwsStateError);
        await expectLater(
          store.importItems(
            pin: '1234',
            imported: [_item('new')],
            mayWrite: () => true,
          ),
          throwsStateError,
        );
        expect(fixture.preferences.data, original);
        expect(fixture.secrets, secrets);
      },
    );
  }

  for (final source in ['legacy', 'secure', 'matching']) {
    test('unmarked $source seed preserves readable records', () async {
      await seedCurrent();
      final originalSeed = fixture.secrets[_seed]!;
      final originalData = NeuraPrefsCache.prefs.getString(_data);
      await NeuraPrefsCache.prefs.remove(_marker);
      if (source != 'secure') {
        await NeuraPrefsCache.prefs.setString(_oldSeed, originalSeed);
      }
      if (source == 'legacy') fixture.secrets.remove(_seed);
      store = MemoryVaultStore.forTesting();
      expect(await store.validatePin('1234'), isTrue);
      expect((await store.getItems(pin: '1234')).single.id, 'original');
      expect(fixture.secrets[_seed], originalSeed);
      expect(NeuraPrefsCache.prefs.getString(_data), originalData);
      expect(
        fixture.preferences.data.containsKey('flutter.$_oldSeed'),
        isFalse,
      );
      expect(fixture.preferences.data['flutter.$_marker'], isTrue);
    });
  }

  test('rejected migration marker keeps the legacy key for retry', () async {
    await seedCurrent();
    final originalSeed = fixture.secrets[_seed]!;
    await NeuraPrefsCache.prefs.setString(_oldSeed, originalSeed);
    await NeuraPrefsCache.prefs.remove(_marker);
    fixture.preferences.refusedWrites.add('flutter.$_marker');
    store = MemoryVaultStore.forTesting();
    expect(await store.validatePin('1234'), isFalse);
    expect(fixture.preferences.data['flutter.$_oldSeed'], originalSeed);
    expect(fixture.secrets[_seed], originalSeed);
    fixture.preferences.refusedWrites.clear();
    store = MemoryVaultStore.forTesting();
    expect(await store.validatePin('1234'), isTrue);
    expect(fixture.preferences.data.containsKey('flutter.$_oldSeed'), isFalse);
  });

  for (final key in [_oldPin, _oldSeed, _oldData]) {
    for (final ignored in [false, true]) {
      test(
        'legacy $key cleanup retries after reopen (ignored: $ignored)',
        () async {
          await seedCurrent();
          final originalSeed = fixture.secrets[_seed]!;
          final originalData = NeuraPrefsCache.prefs.getString(_data);
          final value = key == _oldPin
              ? '1234'
              : key == _oldSeed
                  ? originalSeed
                  : _legacy([_item('original')]);
          await NeuraPrefsCache.prefs.setString(key, value);
          final blocked = ignored
              ? fixture.preferences.ignoredRemovals
              : fixture.preferences.refusedRemovals;
          blocked.add('flutter.$key');
          await expectLater(store.getItems(pin: '1234'), throwsStateError);
          expect(fixture.preferences.data['flutter.$key'], value);
          expect(fixture.preferences.data['flutter.$_data'], originalData);
          expect(fixture.secrets[_seed], originalSeed);
          blocked.clear();
          store = MemoryVaultStore.forTesting();
          expect((await store.getItems(pin: '1234')).single.id, 'original');
          expect(fixture.preferences.data.containsKey('flutter.$key'), isFalse);
        },
      );
    }
  }

  for (final operation in ['hasPinConfigured', 'validatePin']) {
    test(
      'legacy $operation cannot create a key beside orphaned v2 data',
      () async {
        await seedCurrent();
        await NeuraPrefsCache.prefs.setString(_oldPin, '1234');
        await NeuraPrefsCache.prefs.remove(_verifier);
        await NeuraPrefsCache.prefs.remove(_marker);
        fixture.secrets.clear();
        final original = Map.of(fixture.preferences.data);
        store = MemoryVaultStore.forTesting();
        await expectLater(
          operation == 'hasPinConfigured'
              ? store.hasPinConfigured()
              : store.validatePin('1234'),
          throwsStateError,
        );
        expect(fixture.preferences.data, original);
        expect(fixture.secrets, isEmpty);
      },
    );
  }

  test(
    'legacy PIN and XOR data migrate together and remain readable',
    () async {
      await NeuraPrefsCache.prefs.setString(_oldPin, '1234');
      await NeuraPrefsCache.prefs.setString(_oldData, _legacy([_item('old')]));
      expect(await store.hasPinConfigured(), isTrue);
      expect(await store.validatePin('1234'), isTrue);
      expect((await store.getItems(pin: '1234')).single.id, 'old');
      expect(fixture.preferences.data.containsKey('flutter.$_oldPin'), isFalse);
      expect(
        fixture.preferences.data.containsKey('flutter.$_oldData'),
        isFalse,
      );
    },
  );

  test(
    'unreadable legacy data does not replace recovery credentials',
    () async {
      await NeuraPrefsCache.prefs.setString(_oldPin, '1234');
      await NeuraPrefsCache.prefs.setString(_oldData, 'not-valid-ciphertext');
      final original = Map.of(fixture.preferences.data);
      await expectLater(store.hasPinConfigured(), throwsStateError);
      expect(fixture.preferences.data, original);
      expect(fixture.secrets, isEmpty);
    },
  );

  test(
    'divergent legacy records are preserved for explicit recovery',
    () async {
      await seedCurrent();
      final legacy = _legacy([_item('different')]);
      await NeuraPrefsCache.prefs.setString(_oldData, legacy);
      final original = Map.of(fixture.preferences.data);
      await expectLater(store.getItems(pin: '1234'), throwsStateError);
      expect(fixture.preferences.data, original);
    },
  );

  test(
    'repeated conflicting selection skips its existing recovered copy',
    () async {
      await seedCurrent();
      final conflict = _item('original', 'Changed');
      expect(
        await store.importItems(
          pin: '1234',
          imported: [conflict],
          mayWrite: () => true,
        ),
        1,
      );
      store = MemoryVaultStore.forTesting();
      expect(
        await store.importItems(
          pin: '1234',
          imported: [conflict, conflict],
          mayWrite: () => true,
        ),
        0,
      );
      expect(await store.getItems(pin: '1234'), hasLength(2));
    },
  );

  test(
    'conflict retry finds a matching copy beyond a recovered-ID gap',
    () async {
      await seedCurrent();
      await store.importItems(
        pin: '1234',
        imported: [_item('original_recovered_2', 'Changed')],
        mayWrite: () => true,
      );
      expect(
        await store.importItems(
          pin: '1234',
          imported: [_item('original', 'Changed')],
          mayWrite: () => true,
        ),
        0,
      );
      expect(await store.getItems(pin: '1234'), hasLength(2));
    },
  );

  test(
    'retry after an admitted conflicting import commits only one copy',
    () async {
      await seedCurrent();
      store = MemoryVaultStore.forTesting(
        operationTimeout: const Duration(seconds: 3),
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.preferences.beforeSetValue = (key) async {
        if (key == 'flutter.$_data') {
          entered.complete();
          await release.future;
        }
      };
      final conflict = _item('original', 'Changed');
      final failed = expectLater(
        store.importItems(
          pin: '1234',
          imported: [conflict],
          mayWrite: () => true,
        ),
        throwsStateError,
      );
      await entered.future;
      await failed;
      release.complete();
      await store.drainForDataWipe();
      fixture.preferences.beforeSetValue = null;
      store = MemoryVaultStore.forTesting();
      expect(
        await store.importItems(
          pin: '1234',
          imported: [conflict],
          mayWrite: () => true,
        ),
        0,
      );
      expect(await store.getItems(pin: '1234'), hasLength(2));
    },
  );

  test('different conflict versions and unrelated IDs are retained', () async {
    await seedCurrent();
    final first = _item('original', 'First');
    final second = _item('original', 'Second');
    final unrelated = _item('unrelated', 'First');
    expect(
      await store.importItems(
        pin: '1234',
        imported: [first, second, unrelated],
        mayWrite: () => true,
      ),
      3,
    );
    expect(
      await store.importItems(
        pin: '1234',
        imported: [second, first, unrelated],
        mayWrite: () => true,
      ),
      0,
    );
    expect(await store.getItems(pin: '1234'), hasLength(4));
  });
}
