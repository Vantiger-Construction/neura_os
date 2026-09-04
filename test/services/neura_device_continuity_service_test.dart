import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/living_intelligence/device_continuity.dart';
import 'package:neuro_companion/services/neura_device_continuity_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

// NeuraDeviceContinuityService.ensureLoaded() only ever reads from disk once
// per process (guarded by an internal `_loaded` flag), so the "restores from
// disk" scenario must be the very first thing this file's singleton does -
// every later test in this file necessarily runs against the already-loaded
// in-memory state, same as a real app session. The corrupted-store ("fails
// closed") scenario needs its own process and lives in a separate test file
// for the same reason.
const _storeKey = 'neura.device_continuity.paired_devices.v1';

void main() {
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
  });

  final service = NeuraDeviceContinuityService.instance;

  test('ensureLoaded restores a previously paired device from disk', () {
    service.ensureLoaded();

    expect(service.devices, hasLength(1));
    final restored = service.devices.single;
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
    service.ensureLoaded();
    expect(service.devices, hasLength(1));
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
      'verified fingerprint (the registry\'s own guarantee)', () {
    expect(
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
    await service.revokeDevice('new-device');

    final revoked =
        service.devices.firstWhere((d) => d.deviceId == 'new-device');
    expect(revoked.revoked, isTrue);

    final persisted =
        jsonDecode(NeuraPrefsCache.prefs.getString(_storeKey)!) as List;
    final entry = persisted.firstWhere((e) => e['deviceId'] == 'new-device');
    expect(entry['revoked'], isTrue);
  });
}
