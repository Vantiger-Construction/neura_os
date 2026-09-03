import '../neura_safety_policy.dart';

const Duration kDefaultFreshApprovalMaximumLifetime = Duration(minutes: 2);

enum NeuraFreshApprovalOutcome {
  authorized,
  blockedBySafeMode,
  blockedByRecoveryMode,
  directUserGestureRequired,
  explicitApprovalRequired,
  actionLoomAuthorityRequired,
  capabilityNotRegistered,
  criticalCapabilityBlocked,
  moneyMovementBlocked,
  invalidRequest,
  notYetValid,
  expired,
  revoked,
  alreadyConsumed,
  scopeMismatch,
}

class NeuraFreshApprovalReceipt {
  const NeuraFreshApprovalReceipt({
    required this.leaseId,
    required this.outcome,
    required this.evaluatedAtUtc,
  });

  final String leaseId;
  final NeuraFreshApprovalOutcome outcome;
  final DateTime evaluatedAtUtc;

  bool get authorized => outcome == NeuraFreshApprovalOutcome.authorized;
  bool get grantsExecutionAuthority => false;
}

class NeuraFreshApprovalIssue {
  const NeuraFreshApprovalIssue({
    required this.outcome,
    required this.evaluatedAtUtc,
    this.lease,
  });

  final NeuraFreshApprovalOutcome outcome;
  final DateTime evaluatedAtUtc;
  final NeuraFreshApprovalLease? lease;

  bool get issued => lease != null;
  bool get grantsExecutionAuthority => false;
}

class NeuraFreshApprovalScope {
  NeuraFreshApprovalScope({
    required String actionFingerprint,
    required String capabilityId,
    required String capsuleId,
    required String deviceId,
  })  : actionFingerprint = _normalize(
          actionFingerprint,
          fieldName: 'actionFingerprint',
        ),
        capabilityId = _normalize(capabilityId, fieldName: 'capabilityId'),
        capsuleId = _normalize(capsuleId, fieldName: 'capsuleId'),
        deviceId = _normalize(deviceId, fieldName: 'deviceId');

  final String actionFingerprint;
  final String capabilityId;
  final String capsuleId;
  final String deviceId;

  bool matches(NeuraFreshApprovalScope other) {
    return actionFingerprint == other.actionFingerprint &&
        capabilityId == other.capabilityId &&
        capsuleId == other.capsuleId &&
        deviceId == other.deviceId;
  }

  static String _normalize(
    String value, {
    required String fieldName,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized == '*' ||
        normalized.contains('\n') ||
        normalized.contains('\r') ||
        normalized.length > 256) {
      throw ArgumentError.value(
        value,
        fieldName,
        'Approval scope values must be explicit and bounded.',
      );
    }
    return normalized;
  }
}

class NeuraFreshApprovalLeasePolicy {
  const NeuraFreshApprovalLeasePolicy({
    this.maximumLifetime = kDefaultFreshApprovalMaximumLifetime,
  });

  final Duration maximumLifetime;

  NeuraFreshApprovalIssue issue({
    required String leaseId,
    required NeuraFreshApprovalScope scope,
    required DateTime issuedAt,
    required Duration lifetime,
    required NeuraSafetyContext safetyContext,
    required bool explicitApproval,
    required bool capabilityRegistered,
    required bool criticalCapability,
    required bool involvesMoneyMovement,
    required bool safeModeActive,
  }) {
    final evaluatedAtUtc = issuedAt.toUtc();

    NeuraFreshApprovalIssue deny(NeuraFreshApprovalOutcome outcome) {
      return NeuraFreshApprovalIssue(
        outcome: outcome,
        evaluatedAtUtc: evaluatedAtUtc,
      );
    }

    if (safeModeActive) {
      return deny(NeuraFreshApprovalOutcome.blockedBySafeMode);
    }
    if (safetyContext.recoveryMode) {
      return deny(NeuraFreshApprovalOutcome.blockedByRecoveryMode);
    }
    if (!safetyContext.directUserGesture) {
      return deny(NeuraFreshApprovalOutcome.directUserGestureRequired);
    }
    if (!safetyContext.freshApproval || !explicitApproval) {
      return deny(NeuraFreshApprovalOutcome.explicitApprovalRequired);
    }
    if (!capabilityRegistered) {
      return deny(NeuraFreshApprovalOutcome.capabilityNotRegistered);
    }
    if (criticalCapability) {
      return deny(NeuraFreshApprovalOutcome.criticalCapabilityBlocked);
    }
    if (involvesMoneyMovement) {
      return deny(NeuraFreshApprovalOutcome.moneyMovementBlocked);
    }

    final normalizedLeaseId = leaseId.trim();
    final invalidLifetime = lifetime.inMicroseconds <= 0 ||
        maximumLifetime.inMicroseconds <= 0 ||
        lifetime > maximumLifetime;
    if (normalizedLeaseId.isEmpty ||
        normalizedLeaseId == '*' ||
        normalizedLeaseId.length > 128 ||
        invalidLifetime) {
      return deny(NeuraFreshApprovalOutcome.invalidRequest);
    }

    return NeuraFreshApprovalIssue(
      outcome: NeuraFreshApprovalOutcome.authorized,
      evaluatedAtUtc: evaluatedAtUtc,
      lease: NeuraFreshApprovalLease._(
        leaseId: normalizedLeaseId,
        scope: scope,
        issuedAtUtc: evaluatedAtUtc,
        expiresAtUtc: evaluatedAtUtc.add(lifetime),
      ),
    );
  }
}

class NeuraFreshApprovalLease {
  NeuraFreshApprovalLease._({
    required this.leaseId,
    required this.scope,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
  });

  final String leaseId;
  final NeuraFreshApprovalScope scope;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;

  bool _consumed = false;
  bool _revoked = false;

  bool get consumed => _consumed;
  bool get revoked => _revoked;
  bool get grantsExecutionAuthority => false;

  NeuraFreshApprovalReceipt authorizeForActionLoom({
    required DateTime now,
    required NeuraFreshApprovalScope requestedScope,
    required NeuraSafetyContext safetyContext,
    required bool actionLoomAuthority,
    required bool capabilityRegistered,
    required bool criticalCapability,
    required bool involvesMoneyMovement,
    required bool safeModeActive,
  }) {
    final evaluatedAtUtc = now.toUtc();

    NeuraFreshApprovalReceipt receipt(NeuraFreshApprovalOutcome outcome) {
      return NeuraFreshApprovalReceipt(
        leaseId: leaseId,
        outcome: outcome,
        evaluatedAtUtc: evaluatedAtUtc,
      );
    }

    if (safeModeActive) {
      return receipt(NeuraFreshApprovalOutcome.blockedBySafeMode);
    }
    if (safetyContext.recoveryMode) {
      return receipt(NeuraFreshApprovalOutcome.blockedByRecoveryMode);
    }
    if (!safetyContext.directUserGesture) {
      return receipt(NeuraFreshApprovalOutcome.directUserGestureRequired);
    }
    if (!safetyContext.freshApproval) {
      return receipt(NeuraFreshApprovalOutcome.explicitApprovalRequired);
    }
    if (!actionLoomAuthority) {
      return receipt(
        NeuraFreshApprovalOutcome.actionLoomAuthorityRequired,
      );
    }
    if (!capabilityRegistered) {
      return receipt(NeuraFreshApprovalOutcome.capabilityNotRegistered);
    }
    if (criticalCapability) {
      return receipt(NeuraFreshApprovalOutcome.criticalCapabilityBlocked);
    }
    if (involvesMoneyMovement) {
      return receipt(NeuraFreshApprovalOutcome.moneyMovementBlocked);
    }
    if (_revoked) {
      return receipt(NeuraFreshApprovalOutcome.revoked);
    }
    if (_consumed) {
      return receipt(NeuraFreshApprovalOutcome.alreadyConsumed);
    }
    if (evaluatedAtUtc.isBefore(issuedAtUtc)) {
      return receipt(NeuraFreshApprovalOutcome.notYetValid);
    }
    if (!evaluatedAtUtc.isBefore(expiresAtUtc)) {
      return receipt(NeuraFreshApprovalOutcome.expired);
    }
    if (!scope.matches(requestedScope)) {
      return receipt(NeuraFreshApprovalOutcome.scopeMismatch);
    }

    _consumed = true;
    return receipt(NeuraFreshApprovalOutcome.authorized);
  }

  NeuraFreshApprovalReceipt revoke({required DateTime now}) {
    final evaluatedAtUtc = now.toUtc();
    if (_consumed) {
      return NeuraFreshApprovalReceipt(
        leaseId: leaseId,
        outcome: NeuraFreshApprovalOutcome.alreadyConsumed,
        evaluatedAtUtc: evaluatedAtUtc,
      );
    }

    _revoked = true;
    return NeuraFreshApprovalReceipt(
      leaseId: leaseId,
      outcome: NeuraFreshApprovalOutcome.revoked,
      evaluatedAtUtc: evaluatedAtUtc,
    );
  }
}
