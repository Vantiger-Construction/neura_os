import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/living_intelligence/device_continuity.dart';
import 'package:neuro_companion/services/neura_device_continuity_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

const _storeKey = 'neura.device_continuity.paired_devices.v1';

void main() {
  final service = NeuraDeviceContinuityService.instance;
  late List<NeuraDeviceIdentity> initiallyRestored;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      _storeKey: jsonEncode([
        {
          'deviceId': 'restored-device',
          'displayName': 'Restored Phone',
          'publicKeyFingerprint': 'ABCD-EF01-2345-6789',
          'revoked': false,
          'allowedCategories': ['preferences', 'rituals'],
          'allowCloudRelay': false,
        },
      ]),
    });
    await NeuraPrefsCache.init();
    service.ensureLoaded();
    initiallyRestored = service.devices;
  });

  test('ensureLoaded restores a previously paired device from disk', () {
    expect(initiallyRestored, hasLength(1));
    final restored = initiallyRestored.single;
    expect(restored.deviceId, 'restored-device');
    expect(restored.displayName, 'Restored Phone');
    expect(restored.revoked, isFalse);
    expect(
      service.policyFor('restored-device')?.allowedCategories,
      {NeuraContinuityCategory.preferences, NeuraContinuityCategory.rituals},
    );
  });

  test(
      'ensureLoaded is a no-op on a later call (does not duplicate '
      'restored devices)', () {
    final before = service.devices;
    service.ensureLoaded();
    expect(service.devices, orderedEquals(before));
  });

  test('pairDevice adds a new device and persists it', () async {
    await service.pairDevice(
      identity: const NeuraDeviceIdentity(
        deviceId: 'new-device',
        displayName: 'New Laptop',
        publicKeyFingerprint: '1111-2222-3333-4444',
      ),
      policy: NeuraDeviceSyncPolicy(
        allowedCategories: const {NeuraContinuityCategory.derivedInsights},
      ),
      directUserGesture: true,
      fingerprintVerified: true,
    );

    expect(service.devices.map((d) => d.deviceId), contains('new-device'));
    expect(
      service.policyFor('new-device')?.allowedCategories,
      {NeuraContinuityCategory.derivedInsights},
    );

    final persisted =
        jsonDecode(NeuraPrefsCache.prefs.getString(_storeKey)!) as List;
    expect(
      persisted.any((e) => e['deviceId'] == 'new-device'),
      isTrue,
      reason: 'pairDevice should write the new device to disk immediately',
    );
  });

  test(
      'pairDevice refuses to add a device without a direct gesture or '
      'verified fingerprint (the registry\'s own guarantee)', () async {
    await expectLater(
      () => service.pairDevice(
        identity: const NeuraDeviceIdentity(
          deviceId: 'sneaky-device',
          displayName: 'Sneaky',
          publicKeyFingerprint: '0000-0000-0000-0000',
        ),
        policy: NeuraDeviceSyncPolicy(
          allowedCategories: const {NeuraContinuityCategory.preferences},
        ),
        directUserGesture: true,
        fingerprintVerified: false,
      ),
      throwsStateError,
    );
    expect(
      service.devices.map((d) => d.deviceId),
      isNot(contains('sneaky-device')),
    );
  });

  test('revokeDevice marks a device revoked and persists the change', () async {
    const identity = NeuraDeviceIdentity(
      deviceId: 'revocation-target',
      displayName: 'Paired Phone',
      publicKeyFingerprint: 'AAAA-BBBB-CCCC-DDDD',
    );
    await service.pairDevice(
      identity: identity,
      policy: NeuraDeviceSyncPolicy(
        allowedCategories: const {NeuraContinuityCategory.preferences},
      ),
      directUserGesture: true,
      fingerprintVerified: true,
    );
    await service.revokeDevice(identity.deviceId);

    final revoked =
        service.devices.singleWhere((d) => d.deviceId == identity.deviceId);
    expect(revoked.revoked, isTrue);

    final persisted =
        jsonDecode(NeuraPrefsCache.prefs.getString(_storeKey)!) as List;
    final entry =
        persisted.singleWhere((e) => e['deviceId'] == identity.deviceId);
    expect(entry['revoked'], isTrue);
  });
}
