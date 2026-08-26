import 'neura_safety_policy.dart';

enum NeuraCloudInferencePermitState {
  active,
  notYetValid,
  consumed,
  expired,
  revoked,
}

/// A short-lived, purpose-scoped permission to attempt one cloud inference.
///
/// The permit carries no execution authority. It only authorizes a bounded
/// model request to reach an explicitly configured cloud backend after local
/// inference is unavailable.
class NeuraCloudInferencePermit {
  NeuraCloudInferencePermit({
    required this.id,
    required this.purposeId,
    required this.contextCapsuleId,
    required Iterable<String> permittedDataLabels,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
  }) : permittedDataLabels =
            Set<String>.unmodifiable(permittedDataLabels);

  final String id;
  final String purposeId;
  final String contextCapsuleId;
  final Set<String> permittedDataLabels;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;

  bool get grantsExecutionAuthority => false;
}

class NeuraCloudInferenceConsentDecision {
  const NeuraCloudInferenceConsentDecision({
    required this.allowed,
    required this.reason,
    this.state,
  });

  final bool allowed;
  final String reason;
  final NeuraCloudInferencePermitState? state;

  bool get grantsExecutionAuthority => false;
}

class _NeuraCloudInferencePermitRecord {
  _NeuraCloudInferencePermitRecord(this.permit);

  final NeuraCloudInferencePermit permit;
  bool revoked = false;
  int uses = 0;
}

/// In-memory consent registry for cloud model fallback.
///
/// Permits are deliberately one-use, expire quickly, and are matched against
/// the exact model purpose, context capsule, and derived data labels. Safe Mode,
/// Recovery mode, private records, stale approval, and revocation all fail
/// closed.
class NeuraCloudInferenceConsentRegistry {
  NeuraCloudInferenceConsentRegistry({
    required this.safetyPolicy,
    this.maximumTtl = const Duration(minutes: 10),
    this.maximumActivePermits = 8,
  }) {
    if (maximumTtl.inMicroseconds <= 0) {
      throw ArgumentError.value(
        maximumTtl,
        'maximumTtl',
        'Cloud consent TTL must be positive.',
      );
    }
    if (maximumActivePermits <= 0) {
      throw ArgumentError.value(
        maximumActivePermits,
        'maximumActivePermits',
        'At least one active permit slot is required.',
      );
    }
  }

  final NeuraLivingSafetyPolicy safetyPolicy;
  final Duration maximumTtl;
  final int maximumActivePermits;

  final Map<String, _NeuraCloudInferencePermitRecord> _records =
      <String, _NeuraCloudInferencePermitRecord>{};
  int _nextPermitSequence = 0;

  NeuraCloudInferencePermit issue({
    required String purposeId,
    required String contextCapsuleId,
    required Iterable<String> permittedDataLabels,
    required NeuraSafetyContext context,
    Duration ttl = const Duration(minutes: 5),
    DateTime? now,
  }) {
    if (safetyPolicy.safeModeActive) {
      throw StateError('Safe Mode blocks cloud inference consent.');
    }
    if (context.recoveryMode) {
      throw StateError('Recovery mode blocks cloud inference consent.');
    }
    if (!context.directUserGesture || !context.freshApproval) {
      throw StateError(
        'Cloud inference consent requires a direct user gesture and fresh approval.',
      );
    }
    if (!context.allowCloudInference) {
      throw StateError('Cloud inference is not enabled for this request.');
    }
    if (ttl.inMicroseconds <= 0 || ttl > maximumTtl) {
      throw ArgumentError.value(
        ttl,
        'ttl',
        'Cloud consent TTL must be positive and no longer than $maximumTtl.',
      );
    }

    final issuedAt = (now ?? DateTime.now()).toUtc();
    _removeTerminalRecords(issuedAt);
    if (activePermitCount(now: issuedAt) >= maximumActivePermits) {
      throw StateError(
        'The bounded cloud consent permit limit has been reached.',
      );
    }

    final normalizedPurpose = _normalizeScopeValue(
      purposeId,
      fieldName: 'purposeId',
    );
    final normalizedCapsule = _normalizeScopeValue(
      contextCapsuleId,
      fieldName: 'contextCapsuleId',
    );
    final normalizedLabels = _normalizeLabels(permittedDataLabels);
    final permitId =
        'neura-cloud-${issuedAt.microsecondsSinceEpoch}-${_nextPermitSequence++}';
    final permit = NeuraCloudInferencePermit(
      id: permitId,
      purposeId: normalizedPurpose,
      contextCapsuleId: normalizedCapsule,
      permittedDataLabels: normalizedLabels,
      issuedAtUtc: issuedAt,
      expiresAtUtc: issuedAt.add(ttl),
    );
    _records[permit.id] = _NeuraCloudInferencePermitRecord(permit);
    return permit;
  }

  NeuraCloudInferenceConsentDecision validate({
    required String? permitId,
    required String purposeId,
    required String contextCapsuleId,
    required Iterable<String> requestedDataLabels,
    required bool containsPrivateRecords,
    required NeuraSafetyContext context,
    DateTime? now,
  }) {
    return _evaluate(
      permitId: permitId,
      purposeId: purposeId,
      contextCapsuleId: contextCapsuleId,
      requestedDataLabels: requestedDataLabels,
      containsPrivateRecords: containsPrivateRecords,
      context: context,
      now: now,
      consume: false,
    );
  }

  NeuraCloudInferenceConsentDecision validateAndConsume({
    required String? permitId,
    required String purposeId,
    required String contextCapsuleId,
    required Iterable<String> requestedDataLabels,
    required bool containsPrivateRecords,
    required NeuraSafetyContext context,
    DateTime? now,
  }) {
    return _evaluate(
      permitId: permitId,
      purposeId: purposeId,
      contextCapsuleId: contextCapsuleId,
      requestedDataLabels: requestedDataLabels,
      containsPrivateRecords: containsPrivateRecords,
      context: context,
      now: now,
      consume: true,
    );
  }

  NeuraCloudInferenceConsentDecision _evaluate({
    required String? permitId,
    required String purposeId,
    required String contextCapsuleId,
    required Iterable<String> requestedDataLabels,
    required bool containsPrivateRecords,
    required NeuraSafetyContext context,
    required bool consume,
    DateTime? now,
  }) {
    if (safetyPolicy.safeModeActive) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'Safe Mode blocks cloud inference.',
      );
    }
    if (context.recoveryMode) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'Recovery mode blocks cloud inference.',
      );
    }
    if (!context.allowCloudInference) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'Cloud inference is disabled for this request.',
      );
    }
    if (!context.directUserGesture || !context.freshApproval) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'Cloud inference requires direct, fresh in-app approval.',
      );
    }
    if (containsPrivateRecords) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'Private records can never use cloud fallback.',
      );
    }
    if (permitId == null || permitId.trim().isEmpty) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'A purpose-scoped cloud consent permit is required.',
      );
    }

    final record = _records[permitId.trim()];
    if (record == null) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'The cloud consent permit is unknown.',
      );
    }

    final current = (now ?? DateTime.now()).toUtc();
    final state = _stateFor(record, current);
    if (state != NeuraCloudInferencePermitState.active) {
      return NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'The cloud consent permit is ${state.name}.',
        state: state,
      );
    }

    final normalizedPurpose = _normalizeScopeValue(
      purposeId,
      fieldName: 'purposeId',
    );
    final normalizedCapsule = _normalizeScopeValue(
      contextCapsuleId,
      fieldName: 'contextCapsuleId',
    );
    final normalizedLabels = _normalizeLabels(requestedDataLabels);
    final permit = record.permit;

    if (permit.purposeId != normalizedPurpose) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'The cloud consent permit does not cover this model purpose.',
        state: NeuraCloudInferencePermitState.active,
      );
    }
    if (permit.contextCapsuleId != normalizedCapsule) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'The cloud consent permit does not cover this context capsule.',
        state: NeuraCloudInferencePermitState.active,
      );
    }
    if (permit.permittedDataLabels.length != normalizedLabels.length ||
        !permit.permittedDataLabels.containsAll(normalizedLabels)) {
      return const NeuraCloudInferenceConsentDecision(
        allowed: false,
        reason: 'The request contains data labels outside the approved scope.',
        state: NeuraCloudInferencePermitState.active,
      );
    }

    if (consume) {
      record.uses += 1;
    }
    return NeuraCloudInferenceConsentDecision(
      allowed: true,
      reason: consume
          ? 'The one-use cloud consent permit was consumed.'
          : 'The cloud consent permit matches the bounded request.',
      state: consume
          ? NeuraCloudInferencePermitState.consumed
          : NeuraCloudInferencePermitState.active,
    );
  }

  bool revoke(String permitId) {
    final record = _records[permitId.trim()];
    if (record == null) {
      return false;
    }
    record.revoked = true;
    return true;
  }

  NeuraCloudInferencePermitState? stateOf(
    String permitId, {
    DateTime? now,
  }) {
    final record = _records[permitId.trim()];
    if (record == null) {
      return null;
    }
    return _stateFor(record, (now ?? DateTime.now()).toUtc());
  }

  int activePermitCount({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return _records.values
        .where(
          (record) =>
              _stateFor(record, current) ==
              NeuraCloudInferencePermitState.active,
        )
        .length;
  }

  void resetAfterDataWipe() {
    _records.clear();
    _nextPermitSequence = 0;
  }

  NeuraCloudInferencePermitState _stateFor(
    _NeuraCloudInferencePermitRecord record,
    DateTime now,
  ) {
    if (record.revoked) {
      return NeuraCloudInferencePermitState.revoked;
    }
    if (record.uses > 0) {
      return NeuraCloudInferencePermitState.consumed;
    }
    if (now.isBefore(record.permit.issuedAtUtc)) {
      return NeuraCloudInferencePermitState.notYetValid;
    }
    if (!now.isBefore(record.permit.expiresAtUtc)) {
      return NeuraCloudInferencePermitState.expired;
    }
    return NeuraCloudInferencePermitState.active;
  }

  void _removeTerminalRecords(DateTime now) {
    _records.removeWhere((_, record) {
      final state = _stateFor(record, now);
      return state == NeuraCloudInferencePermitState.consumed ||
          state == NeuraCloudInferencePermitState.expired ||
          state == NeuraCloudInferencePermitState.revoked;
    });
  }

  String _normalizeScopeValue(
    String value, {
    required String fieldName,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized == '*' ||
        normalized.contains('\n') ||
        normalized.contains('\r')) {
      throw ArgumentError.value(
        value,
        fieldName,
        'Consent scope values must be explicit and bounded.',
      );
    }
    return normalized;
  }

  Set<String> _normalizeLabels(Iterable<String> labels) {
    final normalized = <String>{};
    for (final label in labels) {
      final value = label.trim();
      if (value.isEmpty ||
          value == '*' ||
          value.contains('\n') ||
          value.contains('\r')) {
        throw ArgumentError.value(
          label,
          'permittedDataLabels',
          'Data labels must be explicit and bounded.',
        );
      }
      normalized.add(value);
    }
    return Set<String>.unmodifiable(normalized);
  }
}
