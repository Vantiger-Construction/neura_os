import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/services/conflict_resolution_service.dart';
import 'package:neuro_companion/services/sync_conflict_log.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    await SyncConflictLog.instance.clear();
  });

  test('record stores only bounded, non-content metadata', () async {
    final log = SyncConflictLog.instance;
    final local = DateTime.utc(2026, 1, 2);
    final remote = DateTime.utc(2026, 1, 3);
    final resolved = DateTime.utc(2026, 1, 3, 1);

    await log.record(
      SyncConflictRecord(
        entryId: 'entry-1',
        resolvedAt: resolved,
        localUpdatedAt: local,
        remoteUpdatedAt: remote,
        winner: ConflictWinner.remote,
      ),
    );

    expect(log.records, hasLength(1));
    final record = log.records.single;
    expect(record.entryId, 'entry-1');
    expect(record.winner, ConflictWinner.remote);
    expect(record.localUpdatedAt.toUtc(), local);
    expect(record.remoteUpdatedAt.toUtc(), remote);
    expect(record.resolvedAt.toUtc(), resolved);
  });

  test('records are newest first', () async {
    final log = SyncConflictLog.instance;
    await log.record(
      SyncConflictRecord(
        entryId: 'entry-1',
        resolvedAt: DateTime.utc(2026, 1, 1),
        localUpdatedAt: DateTime.utc(2026, 1, 1),
        remoteUpdatedAt: DateTime.utc(2026, 1, 1),
        winner: ConflictWinner.local,
      ),
    );
    await log.record(
      SyncConflictRecord(
        entryId: 'entry-2',
        resolvedAt: DateTime.utc(2026, 1, 2),
        localUpdatedAt: DateTime.utc(2026, 1, 2),
        remoteUpdatedAt: DateTime.utc(2026, 1, 2),
        winner: ConflictWinner.remote,
      ),
    );

    expect(log.records.first.entryId, 'entry-2');
    expect(log.records.last.entryId, 'entry-1');
  });

  test('caps stored records at the bound', () async {
    final log = SyncConflictLog.instance;
    for (var i = 0; i < 60; i++) {
      await log.record(
        SyncConflictRecord(
          entryId: 'entry-$i',
          resolvedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          localUpdatedAt: DateTime.utc(2026, 1, 1),
          remoteUpdatedAt: DateTime.utc(2026, 1, 1),
          winner: ConflictWinner.local,
        ),
      );
    }

    expect(log.records.length, 50);
    // The 10 oldest (entry-0..entry-9) were dropped; newest (entry-59) kept.
    expect(log.records.first.entryId, 'entry-59');
    expect(
      log.records.any((r) => r.entryId == 'entry-0'),
      isFalse,
    );
  });

  test('clear removes every record', () async {
    final log = SyncConflictLog.instance;
    await log.record(
      SyncConflictRecord(
        entryId: 'entry-1',
        resolvedAt: DateTime.utc(2026, 1, 1),
        localUpdatedAt: DateTime.utc(2026, 1, 1),
        remoteUpdatedAt: DateTime.utc(2026, 1, 1),
        winner: ConflictWinner.local,
      ),
    );
    expect(log.records, isNotEmpty);

    await log.clear();

    expect(log.records, isEmpty);
  });

  test('resetAfterDataWipe forgets in-memory records', () async {
    final log = SyncConflictLog.instance;
    await log.record(
      SyncConflictRecord(
        entryId: 'entry-1',
        resolvedAt: DateTime.utc(2026, 1, 1),
        localUpdatedAt: DateTime.utc(2026, 1, 1),
        remoteUpdatedAt: DateTime.utc(2026, 1, 1),
        winner: ConflictWinner.local,
      ),
    );

    log.resetAfterDataWipe();

    expect(log.records, isEmpty);
  });

  test('SyncConflictRecord round-trips through toMap / fromMap', () {
    final original = SyncConflictRecord(
      entryId: 'entry-1',
      resolvedAt: DateTime.utc(2026, 1, 3, 1),
      localUpdatedAt: DateTime.utc(2026, 1, 2),
      remoteUpdatedAt: DateTime.utc(2026, 1, 3),
      winner: ConflictWinner.equivalent,
    );
    final restored = SyncConflictRecord.fromMap(original.toMap());

    expect(restored.entryId, original.entryId);
    expect(restored.winner, original.winner);
    expect(restored.resolvedAt.toUtc(), original.resolvedAt.toUtc());
    expect(restored.localUpdatedAt.toUtc(), original.localUpdatedAt.toUtc());
    expect(restored.remoteUpdatedAt.toUtc(), original.remoteUpdatedAt.toUtc());
  });
}
