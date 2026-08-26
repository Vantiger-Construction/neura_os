import '../../intelligence/action_loom.dart';
import '../neura_safety_policy.dart';
import 'action_loom_fresh_approval_gate.dart';
import 'fresh_approval_lease.dart';

/// Binds fresh-approval consumption to a real [NeuraActionLoom] instance.
///
/// Callers cannot supply or spoof the Action Loom authority bit. This extension
/// owns that boundary and passes the concrete loom instance into the commit
/// callback only after exact-scope, expiry, revocation, and replay checks pass.
extension NeuraFreshApprovalActionLoomExtension on NeuraActionLoom {
  Future<NeuraActionLoomGateResult<T>> commitWithFreshApproval<T>({
    required NeuraFreshApprovalLease lease,
    required NeuraFreshApprovalScope requestedScope,
    required NeuraSafetyContext safetyContext,
    required bool capabilityRegistered,
    required bool criticalCapability,
    required bool involvesMoneyMovement,
    required bool safeModeActive,
    required Future<T> Function(NeuraActionLoom loom) commit,
    DateTime? now,
  }) {
    return const NeuraActionLoomFreshApprovalGate().commit<T>(
      lease: lease,
      requestedScope: requestedScope,
      safetyContext: safetyContext,
      actionLoomAuthority: true,
      capabilityRegistered: capabilityRegistered,
      criticalCapability: criticalCapability,
      involvesMoneyMovement: involvesMoneyMovement,
      safeModeActive: safeModeActive,
      actionLoomCommit: () => commit(this),
      now: now,
    );
  }
}
