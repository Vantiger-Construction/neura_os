import '../intelligence/capability_registry.dart';
import '../intelligence/models.dart';
import '../reliability/safe_boot.dart';

enum NeuraAuthorityOutcome {
  allowPreparation,
  requireFreshApproval,
  blocked,
}

/// The minimum caller-supplied facts required to evaluate a Living
/// Intelligence operation.
///
/// [freshApproval] never grants execution authority by itself. It only permits
/// an operation to be prepared for the existing Action Loom boundary.
class NeuraSafetyContext {
  const NeuraSafetyContext({
    this.recoveryMode = false,
    this.directUserGesture = false,
    this.freshApproval = false,
    this.allowCloudInference = false,
  });

  final bool recoveryMode;
  final bool directUserGesture;
  final bool freshApproval;
  final bool allowCloudInference;

  NeuraSafetyContext copyWith({
    bool? recoveryMode,
    bool? directUserGesture,
    bool? freshApproval,
    bool? allowCloudInference,
  }) {
    return NeuraSafetyContext(
      recoveryMode: recoveryMode ?? this.recoveryMode,
      directUserGesture: directUserGesture ?? this.directUserGesture,
      freshApproval: freshApproval ?? this.freshApproval,
      allowCloudInference: allowCloudInference ?? this.allowCloudInference,
    );
  }
}

class NeuraAuthorityDecision {
  const NeuraAuthorityDecision({
    required this.outcome,
    required this.capabilityId,
    required this.reason,
  });

  final NeuraAuthorityOutcome outcome;
  final String capabilityId;
  final String reason;

  bool get mayPrepare => outcome == NeuraAuthorityOutcome.allowPreparation;

  bool get requiresFreshApproval =>
      outcome == NeuraAuthorityOutcome.requireFreshApproval;

  bool get isBlocked => outcome == NeuraAuthorityOutcome.blocked;

  /// Living Intelligence may prepare a proposal, explanation, or draft. The
  /// existing Action Loom remains the only execution authority.
  bool get grantsExecutionAuthority => false;
}

/// Shared fail-closed policy used by every Neura 1.5 subsystem.
class NeuraLivingSafetyPolicy {
  NeuraLivingSafetyPolicy({
    NeuraCapabilityRegistry? registry,
    bool Function()? safeModeReader,
  })  : registry = registry ?? NeuraCapabilityRegistry(),
        _safeModeReader =
            safeModeReader ?? (() => SafeBoot.instance.safeMode.value);

  final NeuraCapabilityRegistry registry;
  final bool Function() _safeModeReader;

  bool get safeModeActive => _safeModeReader();

  NeuraAuthorityDecision evaluate({
    required String capabilityId,
    required NeuraSafetyContext context,
    bool requestsMutation = false,
  }) {
    if (safeModeActive) {
      return NeuraAuthorityDecision(
        outcome: NeuraAuthorityOutcome.blocked,
        capabilityId: capabilityId,
        reason: 'Safe Mode is active.',
      );
    }

    if (context.recoveryMode) {
      return NeuraAuthorityDecision(
        outcome: NeuraAuthorityOutcome.blocked,
        capabilityId: capabilityId,
        reason: 'Recovery mode blocks Living Intelligence operations.',
      );
    }

    final capability = registry.resolve(capabilityId);
    if (capability.id == 'unknown') {
      return NeuraAuthorityDecision(
        outcome: NeuraAuthorityOutcome.blocked,
        capabilityId: capabilityId,
        reason: 'Unknown capabilities fail closed.',
      );
    }

    if (capability.approvalMode == NeuraApprovalMode.blocked ||
        capability.risk == NeuraCapabilityRisk.critical ||
        capability.id == NeuraCapabilityRegistry.moveMoney) {
      return NeuraAuthorityDecision(
        outcome: NeuraAuthorityOutcome.blocked,
        capabilityId: capabilityId,
        reason: 'This capability is not available to Living Intelligence.',
      );
    }

    if (requestsMutation && !context.directUserGesture) {
      return NeuraAuthorityDecision(
        outcome: NeuraAuthorityOutcome.requireFreshApproval,
        capabilityId: capabilityId,
        reason: 'A direct user gesture is required.',
      );
    }

    final requiresApproval =
        capability.approvalMode == NeuraApprovalMode.everyTime ||
            capability.risk == NeuraCapabilityRisk.sensitiveLocal ||
            capability.risk == NeuraCapabilityRisk.external ||
            capability.hasExternalSideEffect;

    if (requiresApproval &&
        (!context.directUserGesture || !context.freshApproval)) {
      return NeuraAuthorityDecision(
        outcome: NeuraAuthorityOutcome.requireFreshApproval,
        capabilityId: capabilityId,
        reason: 'Fresh in-app approval is required.',
      );
    }

    return NeuraAuthorityDecision(
      outcome: NeuraAuthorityOutcome.allowPreparation,
      capabilityId: capabilityId,
      reason: 'The operation may be prepared for the existing review path.',
    );
  }

  bool canUseCloudInference(NeuraSafetyContext context) {
    return !safeModeActive &&
        !context.recoveryMode &&
        context.allowCloudInference;
  }
}
