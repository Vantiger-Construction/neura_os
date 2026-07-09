import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/care/models/trusted_contact.dart';
import 'package:neuro_companion/care/services/trusted_contacts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

TrustedContact _make(String id, {bool emergency = false}) => TrustedContact(
      id: id,
      name: 'Contact $id',
      relationship: 'Friend',
      phoneNumber: '555-0000',
      isEmergency: emergency,
      isProfessional: false,
      notes: '',
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    // Clear all contacts between tests by deleting each one.
    final svc = TrustedContactsService.instance;
    await svc.load();
    final ids = svc.contacts.map((c) => c.id).toList();
    for (final id in ids) {
      await svc.delete(id);
    }
  });

  test('add a contact and retrieve it by id', () async {
    final svc = TrustedContactsService.instance;
    await svc.addOrUpdate(_make('c1'));

    final found = svc.findById('c1');
    expect(found, isNotNull);
    expect(found!.name, 'Contact c1');
    expect(found.id, 'c1');
  });

  test('findById returns null for a missing entry', () async {
    final svc = TrustedContactsService.instance;
    expect(svc.findById('does-not-exist'), isNull);
  });

  test('contacts list reflects added contacts', () async {
    final svc = TrustedContactsService.instance;
    await svc.addOrUpdate(_make('c2'));
    await svc.addOrUpdate(_make('c3'));

    expect(svc.contacts.length, 2);
  });

  test('emergencyContacts returns only emergency entries', () async {
    final svc = TrustedContactsService.instance;
    await svc.addOrUpdate(_make('c4', emergency: false));
    await svc.addOrUpdate(_make('c5', emergency: true));

    expect(svc.emergencyContacts.length, 1);
    expect(svc.emergencyContacts.first.id, 'c5');
  });

  test('addOrUpdate overwrites a contact with the same id', () async {
    final svc = TrustedContactsService.instance;
    await svc.addOrUpdate(_make('c6'));
    await svc.addOrUpdate(_make('c6').copyWith(name: 'Updated'));

    expect(svc.contacts.length, 1);
    expect(svc.findById('c6')!.name, 'Updated');
  });

  test('delete removes the contact without throwing', () async {
    final svc = TrustedContactsService.instance;
    await svc.addOrUpdate(_make('c7'));
    expect(svc.contacts.length, 1);

    await svc.delete('c7');

    expect(svc.contacts, isEmpty);
    expect(svc.findById('c7'), isNull);
  });

  test('delete on a non-existent id does not throw', () async {
    final svc = TrustedContactsService.instance;
    // Must not throw.
    await expectLater(svc.delete('ghost-id'), completes);
  });

  test('TrustedContact.fromMap self-heals missing fields with defaults', () {
    final contact = TrustedContact.fromMap({'id': 'x'});
    expect(contact.id, 'x');
    expect(contact.name, '');
    expect(contact.isEmergency, false);
    expect(contact.isProfessional, false);
  });

  test('TrustedContact round-trips through toMap / fromMap', () {
    final original = _make('rt1', emergency: true);
    final restored = TrustedContact.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.isEmergency, original.isEmergency);
    expect(restored.phoneNumber, original.phoneNumber);
  });
}
