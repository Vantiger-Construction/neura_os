import 'dart:convert';

import '../living_intelligence/device_continuity.dart';
import '../startup/neura_prefs_cache.dart';

/// Wraps [NeuraDeviceContinuityRegistry] (the real pairing/trust policy
/// kernel) with simple JSON persistence so paired devices survive an app
/// restart. Device identities and fingerprints are public-key material, not
/// secret, so plain SharedPreferences storage is the right fit here -
/// unlike the AES-GCM-at-rest treatment private memory content gets in
/// core/memory/memory_crypto.dart.
class NeuraDeviceContinuityService {
  NeuraDeviceContinuityService._();

  static final NeuraDeviceContinuityService instance =
      NeuraDeviceContinuityService._();

  static const _kStoreKey = 'neura.device_continuity.paired_devices.v1';

  final NeuraDeviceContinuityRegistry registry =
      NeuraDeviceContinuityRegistry();
  final Map<String, NeuraDeviceSyncPolicy> _policies = {};
  bool _loaded = false;

  List<NeuraDeviceIdentity> get devices => registry.devices;

  NeuraDeviceSyncPolicy? policyFor(String deviceId) => _policies[deviceId];

  /// Restores previously-paired devices from disk. Safe to call more than
  /// once (no-ops after the first successful load).
  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = NeuraPrefsCache.prefsOrNull?.getString(_kStoreKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      for (final entry in decoded) {
        final map = entry as Map<String, dynamic>;
        final identity = NeuraDeviceIdentity(
          deviceId: map['deviceId'] as String,
          displayName: map['displayName'] as String,
          publicKeyFingerprint: map['publicKeyFingerprint'] as String,
        );
        final categories = (map['allowedCategories'] as List<dynamic>)
            .map(
              (name) => NeuraContinuityCategory.values
                  .firstWhere((category) => category.name == name),
            )
            .toSet();
        final policy = NeuraDeviceSyncPolicy(
          allowedCategories: categories,
          allowCloudRelay: map['allowCloudRelay'] as bool? ?? false,
        );
        // Restoring already-approved state, not making a new pairing
        // decision, so this replays trust rather than re-asserting consent.
        registry.pairDevice(
          identity: identity,
          policy: policy,
          directUserGesture: true,
          fingerprintVerified: true,
        );
        if (map['revoked'] as bool? ?? false) {
          registry.revokeDevice(identity.deviceId);
        }
        _policies[identity.deviceId] = policy;
      }
    } catch (_) {
      // A corrupted store starts fresh rather than blocking the screen.
    }
  }

  Future<void> pairDevice({
    required NeuraDeviceIdentity identity,
    required NeuraDeviceSyncPolicy policy,
    required bool directUserGesture,
    required bool fingerprintVerified,
  }) async {
    registry.pairDevice(
      identity: identity,
      policy: policy,
      directUserGesture: directUserGesture,
      fingerprintVerified: fingerprintVerified,
    );
    _policies[identity.deviceId] = policy;
    await _persist();
  }

  Future<void> revokeDevice(String deviceId) async {
    registry.revokeDevice(deviceId);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = NeuraPrefsCache.prefsOrNull;
    if (prefs == null) return;
    final encoded = jsonEncode([
      for (final device in registry.devices)
        {
          'deviceId': device.deviceId,
          'displayName': device.displayName,
          'publicKeyFingerprint': device.publicKeyFingerprint,
          'revoked': device.revoked,
          'allowedCategories': _policies[device.deviceId]
                  ?.allowedCategories
                  .map((category) => category.name)
                  .toList() ??
              const <String>[],
          'allowCloudRelay':
              _policies[device.deviceId]?.allowCloudRelay ?? false,
        },
    ]);
    try {
      await prefs.setString(_kStoreKey, encoded);
    } catch (_) {
      // Best-effort persistence; the in-memory registry stays correct for
      // this session even if the write fails.
    }
  }
}
