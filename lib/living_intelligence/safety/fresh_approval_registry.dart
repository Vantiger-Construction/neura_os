import '../neura_safety_policy.dart';
import 'fresh_approval_lease.dart';

/// Bounded in-memory lifecycle registry for fresh approval leases.
///
/// Production persistence may wrap this registry with platform secure storage,
/// but raw action arguments must never be persisted. Only precomputed action
/// fingerprints and bounded scope identifiers belong in a lease.
///
/// FLAGGED (2026-09-14, round-2 audit, item 3): `living_intelligence/` is
/// not instantiated from `main.dart` or `startup/` -- this whole subsystem
/// currently appears unreachable from the running app. This class shares
/// its name with the unrelated, live `NeuraFreshApprovalLeaseRegistry` in
/// `intelligence/fresh_approval_lease.dart` (used by `action_loom.dart`
/// for Quest execution), which is a source of confusion even though Dart's
/// per-library scoping keeps them from actually colliding. This file was
/// deliberately left in place rather than deleted -- removing a subsystem
/// someone built is a separate decision from reconciling the systems that
/// are live. Before building on this file further, confirm whether
/// `living_intelligence/` is meant to be wired in, superseded by
/// `intelligence/`, or removed.
class NeuraFreshApprovalLeaseRegistry {
  NeuraFreshApprovalLeaseRegistry({
    this.policy = const NeuraFreshApprovalLeasePolicy(),
    this.maximumActiveLeases = 16,
  }) {
    if (maximumActiveLeases <= 0) {
      throw ArgumentError.value(
        maximumActiveLeases,
        'maximumActiveLeases',
        'At least one bounded lease slot is required.',
      );
    }
  }

  final NeuraFreshApprovalLeasePolicy policy;
  final int maximumActiveLeases;
  final Map<String, NeuraFreshApprovalLease> _leases =
      <String, NeuraFreshApprovalLease>{};

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
    _removeTerminal(evaluatedAtUtc);
    final normalizedLeaseId = leaseId.trim();
    if (_leases.containsKey(normalizedLeaseId) ||
        activeLeaseCount(now: evaluatedAtUtc) >= maximumActiveLeases) {
      return NeuraFreshApprovalIssue(
        outcome: NeuraFreshApprovalOutcome.invalidRequest,
        evaluatedAtUtc: evaluatedAtUtc,
      );
    }

    final issue = policy.issue(
      leaseId: normalizedLeaseId,
      scope: scope,
      issuedAt: evaluatedAtUtc,
      lifetime: lifetime,
      safetyContext: safetyContext,
      explicitApproval: explicitApproval,
      capabilityRegistered: capabilityRegistered,
      criticalCapability: criticalCapability,
      involvesMoneyMovement: involvesMoneyMovement,
      safeModeActive: safeModeActive,
    );
    final lease = issue.lease;
    if (lease != null) {
      _leases[lease.leaseId] = lease;
    }
    return issue;
  }

  NeuraFreshApprovalLease? find(String leaseId) {
    return _leases[leaseId.trim()];
  }

  NeuraFreshApprovalReceipt? revoke(
    String leaseId, {
    DateTime? now,
  }) {
    final lease = find(leaseId);
    if (lease == null) {
      return null;
    }
    return lease.revoke(now: now ?? DateTime.now());
  }

  int activeLeaseCount({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return _leases.values.where((lease) {
      return !lease.consumed &&
          !lease.revoked &&
          !current.isBefore(lease.issuedAtUtc) &&
          current.isBefore(lease.expiresAtUtc);
    }).length;
  }

  void resetAfterDataWipe({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    for (final lease in _leases.values) {
      if (!lease.consumed && !lease.revoked) {
        lease.revoke(now: current);
      }
    }
    _leases.clear();
  }

  void _removeTerminal(DateTime now) {
    _leases.removeWhere((_, lease) {
      return lease.consumed ||
          lease.revoked ||
          !now.isBefore(lease.expiresAtUtc);
    });
  }
}
