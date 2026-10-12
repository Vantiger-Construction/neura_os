import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/local_journal_store.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    await NeuraPrefsCache.prefs.clear();
  });

  test(
    'upsert saves to the existing local journal key without duplicates',
    () async {
      var now = DateTime.utc(2026, 10, 10, 12);
      final store = LocalJournalStore(now: () => now);

      final first = await store.upsertEntry(
        id: 'journal_prompt_2026-10-10',
        content: 'Prompt:\nHow are you?\n\nResponse:\nHere.',
      );
      now = DateTime.utc(2026, 10, 10, 12, 5);
      final repeated = await store.upsertEntry(
        id: 'journal_prompt_2026-10-10',
        content: 'Prompt:\nHow are you?\n\nResponse:\nHere.',
      );

      expect(repeated.updatedAt, first.updatedAt);
      final raw = NeuraPrefsCache.prefs.getStringList(
        LocalJournalStore.storageKey,
      )!;
      expect(raw, hasLength(1));
      expect(jsonDecode(raw.single)['content'], contains('Response:'));
    },
  );

  test(
    'voice transcript save later updates the same local journal entry',
    () async {
      var now = DateTime.utc(2026, 10, 10, 13);
      final store = LocalJournalStore(now: () => now);

      await store.upsertEntry(
        id: 'voice_journal_1',
        content: 'first transcript',
        isVoice: true,
      );
      now = DateTime.utc(2026, 10, 10, 13, 5);
      await store.upsertEntry(
        id: 'voice_journal_1',
        content: 'corrected transcript',
        isVoice: true,
      );

      final entries = await store.loadEntries();
      expect(entries, hasLength(1));
      expect(entries.single.content, 'corrected transcript');
      expect(entries.single.isVoice, isTrue);
    },
  );

  test('journal prompt ids are unique for separate same-day users', () {
    final left = LocalJournalStore.newEntryId('journal_prompt');
    final right = LocalJournalStore.newEntryId('journal_prompt');

    expect(left, startsWith('journal_prompt_'));
    expect(right, startsWith('journal_prompt_'));
    expect(left, isNot(right));
    expect(left, isNot('journal_prompt_2026-10-10'));
  });

  test(
    'failed platform save reloads cache so identical retry writes durably',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final platform = _FlakyPreferencesStore(_Failure.falseResult);
      SharedPreferencesStorePlatform.instance = platform;
      await NeuraPrefsCache.prefs.reload();
      try {
        final store = LocalJournalStore(
          now: () => DateTime.utc(2026, 10, 10, 12),
        );

        await expectLater(
          store.upsertEntry(id: 'entry-1', content: 'same content'),
          throwsA(isA<StateError>()),
        );
        expect(
          NeuraPrefsCache.prefs.getStringList(LocalJournalStore.storageKey),
          isNull,
        );

        await store.upsertEntry(id: 'entry-1', content: 'same content');

        expect(platform.setCalls, 2);
        expect(
          platform.data['flutter.${LocalJournalStore.storageKey}'],
          isA<List<String>>(),
        );
      } finally {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.setMockInitialValues({});
        await NeuraPrefsCache.prefs.reload();
      }
    },
  );

  test(
    'thrown platform save reloads cache so identical retry writes durably',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final platform = _FlakyPreferencesStore(_Failure.throwError);
      SharedPreferencesStorePlatform.instance = platform;
      await NeuraPrefsCache.prefs.reload();
      try {
        final store = LocalJournalStore(
          now: () => DateTime.utc(2026, 10, 10, 12),
        );

        await expectLater(
          store.upsertEntry(id: 'entry-1', content: 'same content'),
          throwsA(isA<StateError>()),
        );
        expect(
          NeuraPrefsCache.prefs.getStringList(LocalJournalStore.storageKey),
          isNull,
        );

        await store.upsertEntry(id: 'entry-1', content: 'same content');

        expect(platform.setCalls, 2);
        expect(
          platform.data['flutter.${LocalJournalStore.storageKey}'],
          isA<List<String>>(),
        );
      } finally {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.setMockInitialValues({});
        await NeuraPrefsCache.prefs.reload();
      }
    },
  );
}

enum _Failure { falseResult, throwError }

final class _FlakyPreferencesStore extends SharedPreferencesStorePlatform {
  _FlakyPreferencesStore(this.failure);

  final _Failure failure;
  final Map<String, Object> data = {};
  int setCalls = 0;

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.from(data);

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setCalls++;
    if (setCalls == 1) {
      if (failure == _Failure.throwError) {
        throw StateError('synthetic platform write failure');
      }
      return false;
    }
    data[key] = value is List<String> ? value.toList() : value;
    return true;
  }
}
