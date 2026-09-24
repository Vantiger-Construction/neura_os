import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/care/models/contact_share_record.dart';
import 'package:neuro_companion/care/services/contact_share_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    final svc = ContactShareService.instance;
    await svc.load();
    final ids = svc.shares.map((s) => s.id).toList();
    for (final id in ids) {
      await svc.removeFromHistory(id);
    }
  });

  test('recordShare stores only bounded, non-content metadata', () async {
    final svc = ContactShareService.instance;
    final start = DateTime(2026, 8, 1);
    final end = DateTime(2026, 8, 30);

    final record = await svc.recordShare(
      contactId: 'contact-1',
      rangeStart: start,
      rangeEnd: end,
      entryCount: 12,
    );

    expect(record.contactId, 'contact-1');
    expect(record.entryCount, 12);
    expect(record.rangeStart, start);
    expect(record.rangeEnd, end);
    expect(svc.shares, hasLength(1));
  });

  test('sharesForContact filters and orders newest first', () async {
    final svc = ContactShareService.instance;
    await svc.recordShare(
      contactId: 'contact-a',
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: DateTime(2026, 1, 7),
      entryCount: 3,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await svc.recordShare(
      contactId: 'contact-b',
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: DateTime(2026, 1, 7),
      entryCount: 4,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await svc.recordShare(
      contactId: 'contact-a',
      rangeStart: DateTime(2026, 2, 1),
      rangeEnd: DateTime(2026, 2, 7),
      entryCount: 5,
    );

    final forA = svc.sharesForContact('contact-a');
    expect(forA, hasLength(2));
    expect(forA.first.entryCount, 5); // Newest first.
    expect(forA.last.entryCount, 3);
    expect(svc.sharesForContact('contact-b'), hasLength(1));
    expect(svc.sharesForContact('does-not-exist'), isEmpty);
  });

  test('removeFromHistory only affects the targeted record', () async {
    final svc = ContactShareService.instance;
    final first = await svc.recordShare(
      contactId: 'contact-1',
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: DateTime(2026, 1, 7),
      entryCount: 2,
    );
    final second = await svc.recordShare(
      contactId: 'contact-1',
      rangeStart: DateTime(2026, 2, 1),
      rangeEnd: DateTime(2026, 2, 7),
      entryCount: 6,
    );

    expect(second.id, isNot(first.id));
    await svc.removeFromHistory(first.id);

    expect(svc.shares, hasLength(1));
    expect(svc.shares.single.entryCount, 6);
  });

  test('clearForContact removes every record for that contact only', () async {
    final svc = ContactShareService.instance;
    await svc.recordShare(
      contactId: 'contact-1',
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: DateTime(2026, 1, 7),
      entryCount: 2,
    );
    await svc.recordShare(
      contactId: 'contact-2',
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: DateTime(2026, 1, 7),
      entryCount: 3,
    );

    await svc.clearForContact('contact-1');

    expect(svc.shares, hasLength(1));
    expect(svc.shares.single.contactId, 'contact-2');
  });

  test('resetAfterDataWipe forgets in-memory history', () async {
    final svc = ContactShareService.instance;
    await svc.recordShare(
      contactId: 'contact-1',
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: DateTime(2026, 1, 7),
      entryCount: 2,
    );
    expect(svc.shares, isNotEmpty);

    svc.resetAfterDataWipe();

    expect(svc.shares, isEmpty);
  });

  test('ContactShareRecord round-trips through toMap / fromMap', () {
    final original = ContactShareRecord(
      id: 'share_1',
      contactId: 'contact-1',
      sharedAt: DateTime(2026, 3, 1, 10, 30),
      rangeStart: DateTime(2026, 2, 1),
      rangeEnd: DateTime(2026, 3, 1),
      entryCount: 9,
    );
    final restored = ContactShareRecord.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.contactId, original.contactId);
    expect(restored.entryCount, original.entryCount);
    expect(restored.sharedAt.toUtc(), original.sharedAt.toUtc());
    expect(restored.rangeStart.toUtc(), original.rangeStart.toUtc());
    expect(restored.rangeEnd.toUtc(), original.rangeEnd.toUtc());
  });

  test('ContactShareRecord.fromMap self-heals missing fields', () {
    final record = ContactShareRecord.fromMap({'id': 'x'});
    expect(record.id, 'x');
    expect(record.contactId, '');
    expect(record.entryCount, 0);
  });
}
