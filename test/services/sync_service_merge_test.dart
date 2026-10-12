import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/models/journal_entry.dart';
import 'package:neuro_companion/services/conflict_resolution_service.dart';
import 'package:neuro_companion/services/sync_conflict_log.dart';
import 'package:neuro_companion/services/sync_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

JournalEntry _entry({
  required String id,
  required String content,
  DateTime? updatedAt,
}) {
  return JournalEntry(
    id: id,
    timestamp: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt,
    content: content,
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    await SyncConflictLog.instance.clear();
  });

  test('a non-divergent entry is merged without logging a conflict', () async {
    final sync = SyncService();
    final merged = await sync.mergeEntries(
      [_entry(id: 'a', content: 'same', updatedAt: DateTime.utc(2026, 1, 1))],
      [_entry(id: 'a', content: 'same', updatedAt: DateTime.utc(2026, 1, 1))],
    );

    expect(merged, hasLength(1));
    expect(SyncConflictLog.instance.records, isEmpty);
  });

  test('a new remote-only entry is added without logging a conflict', () async {
    final sync = SyncService();
    final merged = await sync.mergeEntries(
      [],
      [_entry(id: 'a', content: 'remote only')],
    );

    expect(merged, hasLength(1));
    expect(SyncConflictLog.instance.records, isEmpty);
  });

  test('a divergent conflict resolved by revision time is logged, not silent',
      () async {
    final sync = SyncService();
    final localTime = DateTime.utc(2026, 1, 2);
    final remoteTime = DateTime.utc(2026, 1, 3);

    final merged = await sync.mergeEntries(
      [_entry(id: 'a', content: 'local text', updatedAt: localTime)],
      [_entry(id: 'a', content: 'remote text', updatedAt: remoteTime)],
    );

    expect(merged.single.content, 'remote text');

    final records = SyncConflictLog.instance.records;
    expect(records, hasLength(1));
    expect(records.single.entryId, 'a');
    expect(records.single.winner, ConflictWinner.remote);
    expect(records.single.localUpdatedAt.toUtc(), localTime);
    expect(records.single.remoteUpdatedAt.toUtc(), remoteTime);
  });

  test('the conflict log never contains journal content', () async {
    final sync = SyncService();
    await sync.mergeEntries(
      [
        _entry(
          id: 'a',
          content: 'a private secret',
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ],
      [
        _entry(
          id: 'a',
          content: 'a different private secret',
          updatedAt: DateTime.utc(2026, 1, 3),
        ),
      ],
    );

    final record = SyncConflictLog.instance.records.single;
    final encoded = record.toMap().toString();
    expect(encoded, isNot(contains('private secret')));
  });

  test('legacy prompt ids remain local-only during merge', () async {
    final sync = SyncService();
    final local = JournalEntry(
      id: 'journal_prompt_2026-10-10',
      timestamp: DateTime.utc(2026, 10, 10),
      updatedAt: DateTime.utc(2026, 10, 11),
      content: 'Prompt:\nLocal legacy\n\nResponse:\nKeep local.',
      moodTag: 'journal_prompt:2026-10-10',
    );
    final remote = JournalEntry(
      id: 'journal_prompt_2026-10-10',
      timestamp: DateTime.utc(2026, 10, 10),
      updatedAt: DateTime.utc(2026, 10, 12),
      content: 'Remote record with colliding legacy id.',
      moodTag: 'journal_prompt:2026-10-10',
    );

    final merged = await sync.mergeEntries([local], [remote]);

    expect(merged, hasLength(1));
    expect(merged.single.content, local.content);
    expect(SyncConflictLog.instance.records, isEmpty);
  });
}
