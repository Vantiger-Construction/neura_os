import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/services/neura_device_continuity_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

// Separate file from neura_device_continuity_service_test.dart on purpose:
// NeuraDeviceContinuityService.ensureLoaded() only ever reads from disk once
// per process, so this scenario needs its own fresh singleton/process to
// observe the very first ensureLoaded() call.
const _storeKey = 'neura.device_continuity.paired_devices.v1';

void main() {
  test(
      'a corrupted store fails closed - no device is restored, even when '
      'only one of several entries is malformed', () async {
    SharedPreferences.setMockInitialValues({
      _storeKey: jsonEncode([
        {
          'deviceId': 'good-device',
          'displayName': 'Good Device',
          'publicKeyFingerprint': 'AAAA-BBBB-CCCC-DDDD',
          'revoked': false,
          'allowedCategories': ['preferences'],
          'allowCloudRelay': false,
        },
        {
          // Missing displayName/publicKeyFingerprint - malformed entry.
          'deviceId': 'bad-device',
          'allowedCategories': ['preferences'],
        },
      ]),
    });
    await NeuraPrefsCache.init();

    final service = NeuraDeviceContinuityService.instance;
    service.ensureLoaded();

    expect(
      service.devices,
      isEmpty,
      reason: 'the well-formed entry must not be partially restored '
          'alongside the malformed one',
    );
  });
}
