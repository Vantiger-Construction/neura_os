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
      publicKeyFingerprint:
          publicKeyFingerprint ?? this.publicKeyFingerprint,
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
  }
}
