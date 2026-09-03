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

      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        throw const FormatException('Paired-device store must be a list.');
      }
      final restored = <({
        NeuraDeviceIdentity identity,
        NeuraDeviceSyncPolicy policy,
        bool revoked,
      })>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Invalid paired-device entry.');
        }
        final deviceId = entry['deviceId'];
        final displayName = entry['displayName'];
        final fingerprint = entry['publicKeyFingerprint'];
        final categoryNames = entry['allowedCategories'];
        if (deviceId is! String ||
            deviceId.trim().isEmpty ||
            displayName is! String ||
            displayName.trim().isEmpty ||
            fingerprint is! String ||
            fingerprint.trim().isEmpty ||
            categoryNames is! List<dynamic>) {
          throw const FormatException('Incomplete paired-device entry.');
        }
        final categories = categoryNames.map((name) {
          if (name is! String) {
            throw const FormatException('Invalid continuity category.');
          }
          return NeuraContinuityCategory.values.firstWhere(
            (category) => category.name == name,
            orElse: () =>
                throw const FormatException('Unknown continuity category.'),
          );
        }).toSet();
        final policy = NeuraDeviceSyncPolicy(
          allowedCategories: categories,
          allowCloudRelay: entry['allowCloudRelay'] as bool? ?? false,
        );
        restored.add((
          identity: NeuraDeviceIdentity(
            deviceId: deviceId,
            displayName: displayName,
            publicKeyFingerprint: fingerprint,
          ),
          policy: policy,
          revoked: entry['revoked'] as bool? ?? false,
        ));
      }

      // Apply only after every entry validates, so corrupted storage cannot
      // restore a partial trust set.
      for (final entry in restored) {
        registry.pairDevice(
          identity: entry.identity,
          policy: entry.policy,
          directUserGesture: true,
          fingerprintVerified: true,
        );
        if (entry.revoked) {
          registry.revokeDevice(entry.identity.deviceId);
        }
        _policies[entry.identity.deviceId] = entry.policy;
      }
    } catch (_) {
      // A corrupted store fails closed with no restored trust relationships.
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
