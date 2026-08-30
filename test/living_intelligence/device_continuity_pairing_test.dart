import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/living_intelligence/device_continuity.dart';

void main() {
  final now = DateTime.utc(2026, 8, 30, 12);

  test('pairing requires a live code, gesture, and fingerprint', () {
    final registry = NeuraDeviceContinuityRegistry();
    final session = registry.beginPairing(
      deviceId: 'android',
      now: now,
    );

    expect(session.code, hasLength(6));
    expect(
      () => registry.completePairing(
        identity: const NeuraDeviceIdentity(
          deviceId: 'android',
          displayName: 'Android',
          publicKeyFingerprint: 'android-key',
        ),
        policy: NeuraDeviceSyncPolicy(
          allowedCategories: const [NeuraContinuityCategory.preferences],
        ),
        pairingCode: session.code,
        directUserGesture: false,
        fingerprintVerified: true,
        now: now,
      ),
      throwsStateError,
    );

    registry.completePairing(
      identity: const NeuraDeviceIdentity(
        deviceId: 'android',
        displayName: 'Android',
        publicKeyFingerprint: 'android-key',
      ),
      policy: NeuraDeviceSyncPolicy(
        allowedCategories: const [NeuraContinuityCategory.preferences],
      ),
      pairingCode: session.code,
      directUserGesture: true,
      fingerprintVerified: true,
      now: now,
    );

    expect(registry.devices.single.deviceId, 'android');
  });

  test('expired pairing sessions fail closed', () {
    final registry = NeuraDeviceContinuityRegistry();
    final session = registry.beginPairing(
      deviceId: 'windows',
      now: now,
      ttl: const Duration(minutes: 1),
    );

    expect(
      () => registry.completePairing(
        identity: const NeuraDeviceIdentity(
          deviceId: 'windows',
          displayName: 'Windows',
          publicKeyFingerprint: 'windows-key',
        ),
        policy: NeuraDeviceSyncPolicy(
          allowedCategories: const [NeuraContinuityCategory.preferences],
        ),
        pairingCode: session.code,
        directUserGesture: true,
        fingerprintVerified: true,
        now: now.add(const Duration(minutes: 1)),
      ),
      throwsStateError,
    );
  });

  test('handoff previews require signature and fresh approval', () {
    final registry = NeuraDeviceContinuityRegistry();
    final policy = NeuraDeviceSyncPolicy(
      allowedCategories: const [NeuraContinuityCategory.localQuests],
    );
    registry.pairDevice(
      identity: const NeuraDeviceIdentity(
        deviceId: 'windows',
        displayName: 'Windows',
        publicKeyFingerprint: 'windows-key',
      ),
      policy: policy,
      directUserGesture: true,
      fingerprintVerified: true,
    );
    registry.pairDevice(
      identity: const NeuraDeviceIdentity(
        deviceId: 'android',
        displayName: 'Android',
        publicKeyFingerprint: 'android-key',
      ),
      policy: policy,
      directUserGesture: true,
      fingerprintVerified: true,
    );

    final preview = NeuraHandoffPreview(
      senderDeviceId: 'windows',
      recipientDeviceId: 'android',
      category: NeuraContinuityCategory.localQuests,
      sequence: 1,
      payloadDigest: 'sha256:digest',
      signature: 'platform-signature',
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );

    expect(
      registry.validateHandoffPreview(
        preview,
        signatureVerified: false,
        directUserGesture: true,
        freshApproval: true,
        now: now,
      ).allowed,
      isFalse,
    );
    expect(
      registry.validateHandoffPreview(
        preview,
        signatureVerified: true,
        directUserGesture: true,
        freshApproval: true,
        now: now,
      ).allowed,
      isTrue,
    );
  });

  test('private records cannot use cloud relay policy', () {
    final registry = NeuraDeviceContinuityRegistry();
    final policy = NeuraDeviceSyncPolicy(
      allowedCategories: const [NeuraContinuityCategory.privateRecords],
      allowCloudRelay: true,
    );
    for (final id in ['windows', 'android']) {
      registry.pairDevice(
        identity: NeuraDeviceIdentity(
          deviceId: id,
          displayName: id,
          publicKeyFingerprint: '$id-key',
        ),
        policy: policy,
        directUserGesture: true,
        fingerprintVerified: true,
      );
    }

    final envelope = NeuraContinuityEnvelope(
      senderDeviceId: 'windows',
      recipientDeviceId: 'android',
      category: NeuraContinuityCategory.privateRecords,
      sequence: 1,
      cipherSuite: 'platform-authenticated-encryption',
      ciphertext: const [1],
      nonce: const [2],
      authenticationTag: const [3],
    );

    expect(registry.validateEnvelope(envelope).allowed, isFalse);
  });
}
