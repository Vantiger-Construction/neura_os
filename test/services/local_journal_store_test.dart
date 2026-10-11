import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/local_journal_store.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
