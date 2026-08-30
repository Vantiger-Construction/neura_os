import 'dart:convert';
import 'dart:math';

enum NeuraContinuityCategory {
  preferences,
  localQuests,
  rituals,
  derivedInsights,
  privateRecords,
}

enum NeuraConflictWinner {
  local,
  remote,
}

class NeuraDeviceIdentity {
  const NeuraDeviceIdentity({
    required this.deviceId,
    required this.displayName,
    required this.publicKeyFingerprint,
    this.revoked = false,
  });

  final String deviceId;
  final String displayName;
  final String publicKeyFingerprint;
  final bool revoked;

  NeuraDeviceIdentity copyWith({
    String? displayName,
    String? publicKeyFingerprint,
    bool? revoked,
  }) {
    return NeuraDeviceIdentity(
      deviceId: deviceId,
      displayName: displayName ?? this.displayName,
      publicKeyFingerprint: publicKeyFingerprint ?? this.publicKeyFingerprint,
      revoked: revoked ?? this.revoked,
    );
  }
}

class NeuraDeviceSyncPolicy {
  NeuraDeviceSyncPolicy({
    required Iterable<NeuraContinuityCategory> allowedCategories,
    this.allowCloudRelay = false,
  }) : allowedCategories =
            Set<NeuraContinuityCategory>.unmodifiable(allowedCategories);

  final Set<NeuraContinuityCategory> allowedCategories;
  final bool allowCloudRelay;
}

class NeuraPairingSession {
  NeuraPairingSession({
    required this.deviceId,
    required this.code,
    required this.challenge,
    required DateTime expiresAt,
  }) : expiresAtUtc = expiresAt.toUtc() {
    if (deviceId.trim().isEmpty ||
        code.trim().isEmpty ||
        challenge.trim().isEmpty) {
      throw ArgumentError('A valid pairing session is required.');
    }
  }

  final String deviceId;
  final String code;
  final String challenge;
  final DateTime expiresAtUtc;

  bool isExpired(DateTime now) =>
      !now.toUtc().isBefore(expiresAtUtc);
}

/// A signed, encrypted handoff preview. It contains no plaintext payload and
/// never grants execution authority by itself.
class NeuraHandoffPreview {
  NeuraHandoffPreview({
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.category,
    required this.sequence,
    required this.payloadDigest,
    required this.signature,
    required DateTime createdAt,
    required DateTime expiresAt,
  })  : createdAtUtc = createdAt.toUtc(),
        expiresAtUtc = expiresAt.toUtc() {
    if (senderDeviceId.trim().isEmpty ||
        recipientDeviceId.trim().isEmpty ||
        payloadDigest.trim().isEmpty ||
        signature.trim().isEmpty ||
        sequence < 0 ||
        !expiresAtUtc.isAfter(createdAtUtc)) {
      throw ArgumentError('A valid signed handoff preview is required.');
    }
  }

  final String senderDeviceId;
  final String recipientDeviceId;
  final NeuraContinuityCategory category;
  final int sequence;
  final String payloadDigest;
  final String signature;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;

  bool isExpired(DateTime now) =>
      !now.toUtc().isBefore(expiresAtUtc);
}
/// An already-encrypted payload produced by a platform crypto bridge.
///
/// This class deliberately does not accept plaintext.
class NeuraContinuityEnvelope {
  NeuraContinuityEnvelope({
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.category,
    required this.sequence,
    required this.cipherSuite,
    required Iterable<int> ciphertext,
    required Iterable<int> nonce,
    required Iterable<int> authenticationTag,
  })  : ciphertext = List<int>.unmodifiable(ciphertext),
        nonce = List<int>.unmodifiable(nonce),
        authenticationTag = List<int>.unmodifiable(authenticationTag) {
    if (this.ciphertext.isEmpty ||
        this.nonce.isEmpty ||
        this.authenticationTag.isEmpty) {
      throw ArgumentError(
        'Continuity envelopes must contain authenticated encrypted bytes.',
      );
    }
  }

  final String senderDeviceId;
  final String recipientDeviceId;
  final NeuraContinuityCategory category;
  final int sequence;
  final String cipherSuite;
  final List<int> ciphertext;
  final List<int> nonce;
  final List<int> authenticationTag;
}

class NeuraContinuityDecision {
  const NeuraContinuityDecision({
    required this.allowed,
    required this.reason,
  });

  final bool allowed;
  final String reason;
}

class NeuraContinuityRecordMetadata {
  const NeuraContinuityRecordMetadata({
    required this.updatedAt,
    required this.deviceId,
    required this.revision,
  });

  final DateTime updatedAt;
  final String deviceId;
  final int revision;
}

class NeuraDeviceContinuityRegistry {
  final Map<String, NeuraDeviceIdentity> _devices =
      <String, NeuraDeviceIdentity>{};
  final Map<String, NeuraDeviceSyncPolicy> _policies =
      <String, NeuraDeviceSyncPolicy>{};
  final Map<String, int> _lastSequenceBySender = <String, int>{};
  final Map<String, NeuraPairingSession> _pairingSessions =
      <String, NeuraPairingSession>{};

  /// Starts a short-lived, single-device pairing ceremony.
  /// The code is for human confirmation; the challenge is for the
  /// platform crypto bridge to bind the two device identities.
  NeuraPairingSession beginPairing({
    required String deviceId,
    DateTime? now,
    Duration ttl = const Duration(minutes: 5),
  }) {
    final id = deviceId.trim();
    if (id.isEmpty) throw ArgumentError('A device id is required.');
    if (ttl.compareTo(Duration.zero) <= 0) {
      throw ArgumentError('Pairing-session lifetime must be positive.');
    }
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final session = NeuraPairingSession(
      deviceId: id,
      code: _newPairingCode(),
      challenge: _newPairingChallenge(),
      expiresAt: issuedAt.add(ttl),
    );
    _pairingSessions[id] = session;
    return session;
  }

  /// Completes pairing only after fresh human confirmation and fingerprint
  /// verification. A failed attempt does not consume the session; expiry
  /// or successful pairing does.
  void completePairing({
    required NeuraDeviceIdentity identity,
    required NeuraDeviceSyncPolicy policy,
    required String pairingCode,
    required bool directUserGesture,
    required bool fingerprintVerified,
    DateTime? now,
  }) {
    if (!directUserGesture || !fingerprintVerified) {
      throw StateError(
        'Device pairing requires a direct gesture and verified fingerprint.',
      );
    }
    final id = identity.deviceId.trim();
    final session = _pairingSessions[id];
    if (session == null) {
      throw StateError('No active pairing session exists for this device.');
    }
    final current = (now ?? DateTime.now()).toUtc();
    if (session.isExpired(current)) {
      _pairingSessions.remove(id);
      throw StateError('The pairing code has expired.');
    }
    if (pairingCode.trim() != session.code) {
      throw StateError('The pairing code did not match.');
    }
    pairDevice(
      identity: identity,
      policy: policy,
      directUserGesture: directUserGesture,
      fingerprintVerified: fingerprintVerified,
    );
    _pairingSessions.remove(id);
  }

  static String _newPairingCode() =>
      Random.secure().nextInt(1000000).toString().padLeft(6, '0');

  static String _newPairingChallenge() => base64UrlEncode(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
  List<NeuraDeviceIdentity> get devices =>
      List<NeuraDeviceIdentity>.unmodifiable(_devices.values);

  void pairDevice({
    required NeuraDeviceIdentity identity,
    required NeuraDeviceSyncPolicy policy,
    required bool directUserGesture,
    required bool fingerprintVerified,
  }) {
    if (!directUserGesture || !fingerprintVerified) {
      throw StateError(
        'Device pairing requires a direct gesture and verified fingerprint.',
      );
    }

    if (identity.deviceId.trim().isEmpty ||
        identity.publicKeyFingerprint.trim().isEmpty) {
      throw ArgumentError('A device id and public-key fingerprint are needed.');
    }

    _devices[identity.deviceId] = identity.copyWith(revoked: false);
    _policies[identity.deviceId] = policy;
  }

  void revokeDevice(String deviceId) {
    final current = _devices[deviceId];
    if (current != null) {
      _devices[deviceId] = current.copyWith(revoked: true);
    }
  }

  void revokeAll() {
    for (final entry in _devices.entries.toList()) {
      _devices[entry.key] = entry.value.copyWith(revoked: true);
    }
    _lastSequenceBySender.clear();
  }

  /// Validates the human-facing handoff preview. The caller must still
  /// validate the authenticated ciphertext with [validateEnvelope] before
  /// applying it. This method never mutates device state or grants action
  /// authority.
  NeuraContinuityDecision validateHandoffPreview(
    NeuraHandoffPreview preview, {
    required bool signatureVerified,
    required bool directUserGesture,
    required bool freshApproval,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    if (!directUserGesture || !freshApproval) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'Handoff apply requires a direct gesture and fresh approval.',
      );
    }
    if (!signatureVerified) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'The handoff signature was not verified by the crypto bridge.',
      );
    }
    if (preview.isExpired(current)) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'The handoff preview has expired.',
      );
    }

    final sender = _devices[preview.senderDeviceId];
    final recipient = _devices[preview.recipientDeviceId];
    final senderPolicy = _policies[preview.senderDeviceId];
    final recipientPolicy = _policies[preview.recipientDeviceId];
    if (sender == null || recipient == null ||
        sender.revoked || recipient.revoked ||
        senderPolicy == null || recipientPolicy == null) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'Both active devices must be paired before handoff.',
      );
    }
    if (!senderPolicy.allowedCategories.contains(preview.category) ||
        !recipientPolicy.allowedCategories.contains(preview.category)) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'The handoff category is not enabled on both devices.',
      );
    }
    if (preview.category == NeuraContinuityCategory.privateRecords &&
        (senderPolicy.allowCloudRelay || recipientPolicy.allowCloudRelay)) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'Private records cannot use a cloud-relay policy.',
      );
    }
    final lastSequence = _lastSequenceBySender[preview.senderDeviceId] ?? -1;
    if (preview.sequence <= lastSequence) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'Replay or out-of-order handoff preview rejected.',
      );
    }
    return const NeuraContinuityDecision(
      allowed: true,
      reason: 'The signed handoff preview may be shown for guarded apply.',
    );
  }
  NeuraContinuityDecision validateEnvelope(
    NeuraContinuityEnvelope envelope,
  ) {
    final sender = _devices[envelope.senderDeviceId];
    final recipient = _devices[envelope.recipientDeviceId];

    if (sender == null || recipient == null) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'Both devices must be paired.',
      );
    }

    if (sender.revoked || recipient.revoked) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'A revoked device cannot participate in continuity.',
      );
    }

    final senderPolicy = _policies[sender.deviceId];
    final recipientPolicy = _policies[recipient.deviceId];
    if (senderPolicy == null ||
        recipientPolicy == null ||
        !senderPolicy.allowedCategories.contains(envelope.category) ||
        !recipientPolicy.allowedCategories.contains(envelope.category)) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'The data category is not enabled on both devices.',
      );
    }

    if (envelope.category == NeuraContinuityCategory.privateRecords &&
        (senderPolicy.allowCloudRelay || recipientPolicy.allowCloudRelay)) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'Private records cannot use a cloud-relay policy.',
      );
    }

    final lastSequence = _lastSequenceBySender[sender.deviceId] ?? -1;
    if (envelope.sequence <= lastSequence) {
      return const NeuraContinuityDecision(
        allowed: false,
        reason: 'Replay or out-of-order continuity envelope rejected.',
      );
    }

    _lastSequenceBySender[sender.deviceId] = envelope.sequence;
    return const NeuraContinuityDecision(
      allowed: true,
      reason: 'The authenticated encrypted envelope may be applied.',
    );
  }

  NeuraConflictWinner resolveMetadataConflict({
    required NeuraContinuityRecordMetadata local,
    required NeuraContinuityRecordMetadata remote,
  }) {
    final revisionCompare = local.revision.compareTo(remote.revision);
    if (revisionCompare != 0) {
      return revisionCompare > 0
          ? NeuraConflictWinner.local
          : NeuraConflictWinner.remote;
    }

    final timeCompare = local.updatedAt.compareTo(remote.updatedAt);
    if (timeCompare != 0) {
      return timeCompare > 0
          ? NeuraConflictWinner.local
          : NeuraConflictWinner.remote;
    }

    return local.deviceId.compareTo(remote.deviceId) <= 0
        ? NeuraConflictWinner.local
        : NeuraConflictWinner.remote;
  }

  void resetAfterDataWipe() {
    revokeAll();
    _policies.clear();
    _pairingSessions.clear();
  }
}
