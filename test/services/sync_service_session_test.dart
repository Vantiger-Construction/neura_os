import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/models/journal_entry.dart';
import 'package:neuro_companion/services/sync_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

JournalEntry entry(String text, int day) => JournalEntry(
    id: 'one',
    timestamp: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026, 1, day),
    content: text);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  test('newer remote revision is merged before any upload', () async {
    var local = [entry('old local', 1)];
    var pushes = 0;
    final service = SyncService.forTesting(
      loadLocal: () async => List.of(local),
      saveLocal: (value) async {
        local = value;
      },
      fetchPage: (_, __, ___) async => [entry('new remote', 2)],
      pushRevision: (value, _) async {
        pushes++;
        return value;
      },
      allowed: () => true,
      userId: () => 'user',
      online: () async => true,
    );
    final result = await service.syncAll();
    expect(result.succeeded, true);
    expect(local.single.content, 'new remote');
    expect(pushes, 0);
  });
  test('local edit made during upload survives newer server acknowledgement',
      () async {
    var local = [entry('to upload', 2)];
    final service = SyncService.forTesting(
      loadLocal: () async => List.of(local),
      saveLocal: (value) async {
        local = value;
      },
      fetchPage: (_, __, ___) async => [entry('old cloud', 1)],
      pushRevision: (value, expected) async {
        expect(expected, DateTime.utc(2026, 1, 1));
        local = [entry('edited while uploading', 3)];
        return entry('to upload', 4);
      },
      allowed: () => true,
      userId: () => 'user',
      online: () async => true,
    );
    final result = await service.syncAll();
    expect(local.single.content, 'edited while uploading');
    expect(result.outcome, SyncOutcome.retryNeeded);
    expect(result.pending, 1);
  });
  test('account change during fetch prevents local writes and upload',
      () async {
    var user = 'first';
    var saves = 0;
    var pushes = 0;
    final service = SyncService.forTesting(
      loadLocal: () async => [entry('local', 1)],
      saveLocal: (_) async {
        saves++;
      },
      fetchPage: (_, __, ___) async {
        user = 'second';
        return [entry('remote', 2)];
      },
      pushRevision: (value, _) async {
        pushes++;
        return value;
      },
      allowed: () => true,
      userId: () => user,
      online: () async => true,
    );
    expect((await service.syncAll()).outcome, SyncOutcome.interrupted);
    expect(saves, 0);
    expect(pushes, 0);
  });
  test('offline attempt does not fetch, save or upload', () async {
    var calls = 0;
    final service = SyncService.forTesting(
      loadLocal: () async {
        calls++;
        return [];
      },
      saveLocal: (_) async {
        calls++;
      },
      fetchPage: (_, __, ___) async {
        calls++;
        return [];
      },
      pushRevision: (value, _) async {
        calls++;
        return value;
      },
      allowed: () => true,
      userId: () => 'user',
      online: () async => false,
    );
    expect((await service.syncAll()).outcome, SyncOutcome.offline);
    expect(calls, 0);
  });

  test('legacy prompt ids are not uploaded during sync', () async {
    final legacy = JournalEntry(
      id: 'journal_prompt_2026-10-10',
      timestamp: DateTime.utc(2026, 10, 10),
      updatedAt: DateTime.utc(2026, 10, 11),
      content: 'Prompt:\nLegacy prompt\n\nResponse:\nLocal response.',
      moodTag: 'journal_prompt:2026-10-10',
    );
    var pushes = 0;
    final service = SyncService.forTesting(
      loadLocal: () async => [legacy],
      saveLocal: (_) async {},
      fetchPage: (_, __, ___) async => [],
      pushRevision: (value, _) async {
        pushes++;
        return value;
      },
      allowed: () => true,
      userId: () => 'user',
      online: () async => true,
    );

    final result = await service.syncAll();

    expect(result.outcome, SyncOutcome.complete);
    expect(pushes, 0);
  });
}
