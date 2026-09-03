import '../neura_safety_policy.dart';
import 'fresh_approval_lease.dart';

class NeuraActionLoomGateResult<T> {
  const NeuraActionLoomGateResult({
    required this.receipt,
    required this.committed,
    this.value,
  });

  final NeuraFreshApprovalReceipt receipt;
  final bool committed;
  final T? value;

  bool get grantsExecutionAuthority => false;
}

/// Final anti-replay gate to be called from an Action Loom mutation boundary.
///
/// The callback is never invoked unless the lease still matches the exact
/// action, capsule, capability, and device scope and every safety boundary is
/// revalidated at commit time. A successful authorization consumes the lease
/// before the callback starts, so a thrown commit cannot be silently replayed.
class NeuraActionLoomFreshApprovalGate {
  const NeuraActionLoomFreshApprovalGate();

  Future<NeuraActionLoomGateResult<T>> commit<T>({
    required NeuraFreshApprovalLease lease,
    required NeuraFreshApprovalScope requestedScope,
    required NeuraSafetyContext safetyContext,
    required bool actionLoomAuthority,
    required bool capabilityRegistered,
    required bool criticalCapability,
    required bool involvesMoneyMovement,
    required bool safeModeActive,
    required Future<T> Function() actionLoomCommit,
    DateTime? now,
  }) async {
    final receipt = lease.authorizeForActionLoom(
      now: now ?? DateTime.now(),
      requestedScope: requestedScope,
      safetyContext: safetyContext,
      actionLoomAuthority: actionLoomAuthority,
      capabilityRegistered: capabilityRegistered,
      criticalCapability: criticalCapability,
      involvesMoneyMovement: involvesMoneyMovement,
      safeModeActive: safeModeActive,
    );
    if (!receipt.authorized) {
      return NeuraActionLoomGateResult<T>(
        receipt: receipt,
        committed: false,
      );
    }

    final value = await actionLoomCommit();
    return NeuraActionLoomGateResult<T>(
      receipt: receipt,
      committed: true,
      value: value,
    );
  }
}
