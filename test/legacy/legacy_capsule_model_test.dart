import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_companion/src/modules/legacy/models/legacy_capsule.dart';

LegacyCapsule _minimal() => LegacyCapsule(
      id: 'test-id',
      title: 'My Capsule',
      body: 'Hello world',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    );

void main() {
  group('LegacyCapsule model', () {
    test('round-trips through toMap / fromMap', () {
      final original = _minimal();
      final restored = LegacyCapsule.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.isSealed, false);
      expect(restored.isEncrypted, false);
      expect(restored.attachments, isEmpty);
      expect(restored.recipients, isEmpty);
    });

    test('round-trips through toJson / fromJson', () {
      final original = _minimal();
      final json = original.toJson();
      final restored = LegacyCapsule.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.body, original.body);
    });

    test('fromMap with empty map returns defaults without throwing', () {
      final capsule = LegacyCapsule.fromMap({});

      expect(capsule.id, '');
      expect(capsule.title, '');
      expect(capsule.body, '');
      expect(capsule.isSealed, false);
      expect(capsule.isEncrypted, false);
      expect(capsule.attachments, isEmpty);
      expect(capsule.deliveryTrigger, 'manual');
      expect(capsule.deliveryFormat, 'zip');
    });

    test('fromJson throws on corrupted JSON (empty-vault skip guard)', () {
      // LegacyVaultService.listCapsules() catches this and skips the entry.
      expect(
        () => LegacyCapsule.fromJson('not-valid-json{{{'),
        throwsA(anything),
      );
    });

    test('isLocked is false when unlockAt is null', () {
      expect(_minimal().isLocked, false);
    });

    test('isLocked is true when unlockAt is in the future', () {
      final future = DateTime.now().add(const Duration(days: 1));
      final capsule = _minimal().copyWith(unlockAt: future);
      expect(capsule.isLocked, true);
    });

    test('isLocked is false when unlockAt is in the past', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final capsule = _minimal().copyWith(unlockAt: past);
      expect(capsule.isLocked, false);
    });

    test('encrypted capsule survives round-trip with payload fields', () {
      final encrypted = _minimal().copyWith(
        body: '',
        isEncrypted: true,
        cipherTextB64: 'abc123',
        nonceB64: 'nonce',
        macB64: 'mac',
        saltB64: 'salt',
      );
      final restored = LegacyCapsule.fromMap(encrypted.toMap());

      expect(restored.isEncrypted, true);
      expect(restored.cipherTextB64, 'abc123');
      expect(restored.nonceB64, 'nonce');
      expect(restored.body, '');
    });

    test('sealed capsule flag survives round-trip', () {
      final sealed = _minimal().copyWith(isSealed: true);
      final restored = LegacyCapsule.fromMap(sealed.toMap());
      expect(restored.isSealed, true);
    });
  });

  group('LegacyCapsule delivery fields', () {
    test('deliveryContactIds survives round-trip', () {
      final capsule = _minimal().copyWith(
        deliveryEnabled: true,
        deliveryTrigger: 'deadman',
        deliveryContactIds: ['contact-1', 'contact-2'],
      );
      final restored = LegacyCapsule.fromMap(capsule.toMap());

      expect(restored.deliveryEnabled, true);
      expect(restored.deliveryTrigger, 'deadman');
      expect(restored.deliveryContactIds, ['contact-1', 'contact-2']);
    });

    test('fromMap with null deliveryTrigger defaults to manual', () {
      final map = _minimal().toMap()..['deliveryTrigger'] = null;
      final capsule = LegacyCapsule.fromMap(map);
      expect(capsule.deliveryTrigger, 'manual');
    });

    test('fromMap with null deliveryFormat defaults to zip', () {
      final map = _minimal().toMap()..['deliveryFormat'] = null;
      final capsule = LegacyCapsule.fromMap(map);
      expect(capsule.deliveryFormat, 'zip');
    });
  });
}
