import '../intelligence/capability_registry.dart';
import '../persona/models/neura_audience.dart';
import 'android_intelligence_bridge.dart';
import 'cloud_inference_consent.dart';
import 'compassionate_response_policy.dart';
import 'context_capsules.dart';
import 'conversation_turn_coordinator.dart';
import 'device_continuity.dart';
import 'future_paths_simulator.dart';
import 'neura_safety_policy.dart';
import 'presence_engine.dart';
import 'private_neural_core.dart';
import 'reflex_safety_layer.dart';
import 'safety/action_loom_fresh_approval_gate.dart';
import 'safety/fresh_approval_lease.dart';
import 'safety/fresh_approval_registry.dart';
import 'self_healing_runtime.dart';
import 'signed_skill_capsules.dart';
import 'trust_lens.dart';

class NeuraLivingIntelligenceStatus {
  const NeuraLivingIntelligenceStatus({
    required this.enabled,
    required this.safeModeBlocked,
    required this.localModelBackends,
    required this.pairedDevices,
    this.activeCloudPermits = 0,
    this.activeConversationTurn = false,
    this.activeFreshApprovalLeases = 0,
  });

  final bool enabled;
  final bool safeModeBlocked;
  final int localModelBackends;
  final int pairedDevices;
  final int activeCloudPermits;
  final bool activeConversationTurn;
  final int activeFreshApprovalLeases;
}

/// Coordination facade for Neura 1.5 and its bounded 1.5.1 safety upgrade.
///
/// The facade is disabled by default. It exposes policy and preparation
/// services only; Action Loom remains the sole authority for real mutations.
class NeuraLivingIntelligenceRuntime {
  NeuraLivingIntelligenceRuntime({
    required this.safetyPolicy,
    required this.cloudConsent,
    required this.modelRouter,
    required this.reflexLayer,
    required this.trustLens,
    required this.contextCapsules,
    required this.skillValidator,
    required this.skillHealth,
    required this.presenceEngine,
    required this.responsePolicy,
    required this.turnCoordinator,
    required this.freshApprovalLeases,
    required this.actionLoomApprovalGate,
    required this.futurePaths,
    required this.selfHealing,
    required this.androidBridge,
    required this.continuity,
  });

  factory NeuraLivingIntelligenceRuntime.create({
    Iterable<NeuraModelBackend> modelBackends = const <NeuraModelBackend>[],
    NeuraReflexBindings reflexBindings = const NeuraReflexBindings(),
    NeuraPresenceBindings presenceBindings = const NeuraPresenceBindings(),
    NeuraSkillSignatureVerifier signatureVerifier =
        const NeuraDenyAllSkillSignatureVerifier(),
    bool Function()? safeModeReader,
  }) {
    final safetyPolicy = NeuraLivingSafetyPolicy(
      safeModeReader: safeModeReader,
    );
    final cloudConsent = NeuraCloudInferenceConsentRegistry(
      safetyPolicy: safetyPolicy,
    );
    final modelRouter = NeuraLocalModelRouter(
      safetyPolicy: safetyPolicy,
      cloudConsentRegistry: cloudConsent,
      backends: modelBackends,
    );
    final presenceEngine = NeuraPresenceEngine(
      bindings: presenceBindings,
    );
    const responsePolicy = NeuraCompassionateResponsePolicy();
    final turnCoordinator = NeuraConversationTurnCoordinator(
      modelRouter: modelRouter,
      presenceEngine: presenceEngine,
    );
    final freshApprovalLeases = NeuraFreshApprovalLeaseRegistry();
    const actionLoomApprovalGate = NeuraActionLoomFreshApprovalGate();

    return NeuraLivingIntelligenceRuntime(
      safetyPolicy: safetyPolicy,
      cloudConsent: cloudConsent,
      modelRouter: modelRouter,
      reflexLayer: NeuraReflexSafetyLayer(
        bindings: reflexBindings,
      ),
      trustLens: const NeuraTrustLens(),
      contextCapsules: NeuraContextCapsuleRegistry(),
      skillValidator: NeuraSignedSkillValidator(
        signatureVerifier: signatureVerifier,
      ),
      skillHealth: NeuraSkillHealthRegistry(),
      presenceEngine: presenceEngine,
      responsePolicy: responsePolicy,
      turnCoordinator: turnCoordinator,
      freshApprovalLeases: freshApprovalLeases,
      actionLoomApprovalGate: actionLoomApprovalGate,
      futurePaths: const NeuraFuturePathsSimulator(),
      selfHealing: NeuraSelfHealingRuntime(),
      androidBridge: const NeuraAndroidIntelligenceBridge(),
      continuity: NeuraDeviceContinuityRegistry(),
    );
  }

  final NeuraLivingSafetyPolicy safetyPolicy;
  final NeuraCloudInferenceConsentRegistry cloudConsent;
  final NeuraLocalModelRouter modelRouter;
  final NeuraReflexSafetyLayer reflexLayer;
  final NeuraTrustLens trustLens;
  final NeuraContextCapsuleRegistry contextCapsules;
  final NeuraSignedSkillValidator skillValidator;
  final NeuraSkillHealthRegistry skillHealth;
  final NeuraPresenceEngine presenceEngine;
  final NeuraCompassionateResponsePolicy responsePolicy;
  final NeuraConversationTurnCoordinator turnCoordinator;
  final NeuraFreshApprovalLeaseRegistry freshApprovalLeases;
  final NeuraActionLoomFreshApprovalGate actionLoomApprovalGate;
  final NeuraFuturePathsSimulator futurePaths;
  final NeuraSelfHealingRuntime selfHealing;
  final NeuraAndroidIntelligenceBridge androidBridge;
  final NeuraDeviceContinuityRegistry continuity;

  bool _enabled = false;

  bool get enabled => _enabled;

  NeuraLivingIntelligenceStatus get status {
    return NeuraLivingIntelligenceStatus(
      enabled: _enabled,
      safeModeBlocked: safetyPolicy.safeModeActive,
      localModelBackends:
          modelRouter.backends.where((backend) => backend.runsLocally).length,
      pairedDevices: continuity.devices.length,
      activeCloudPermits: cloudConsent.activePermitCount(),
      activeConversationTurn: turnCoordinator.hasActiveTurn,
      activeFreshApprovalLeases: freshApprovalLeases.activeLeaseCount(),
    );
  }

  void setEnabled(
    bool value, {
    required NeuraSafetyContext context,
  }) {
    if (value && (safetyPolicy.safeModeActive || context.recoveryMode)) {
      throw StateError(
        'Living Intelligence cannot be enabled in Safe Mode or Recovery mode.',
      );
    }

    _enabled = value;
    modelRouter.enabled = value;
    if (!value) {
      turnCoordinator.cancelActiveTurn();
      freshApprovalLeases.resetAfterDataWipe();
    }
  }

  NeuraAuthorityDecision evaluateCapability({
    required String capabilityId,
    required NeuraSafetyContext context,
    bool requestsMutation = false,
  }) {
    if (!_enabled) {
      return NeuraAuthorityDecision(
        outcome: NeuraAuthorityOutcome.blocked,
        capabilityId: capabilityId,
        reason: 'Living Intelligence is disabled.',
      );
    }

    return safetyPolicy.evaluate(
      capabilityId: capabilityId,
      context: context,
      requestsMutation: requestsMutation,
    );
  }

  NeuraAuthorityDecision evaluateLocalPlanDraft(
    NeuraSafetyContext context,
  ) {
    return evaluateCapability(
      capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
      context: context,
      requestsMutation: true,
    );
  }

  NeuraCloudInferencePermit issueCloudInferencePermit({
    required NeuraModelPurpose purpose,
    required String contextCapsuleId,
    required Iterable<String> permittedDataLabels,
    required NeuraSafetyContext context,
    Duration ttl = const Duration(minutes: 5),
    DateTime? now,
  }) {
    if (!_enabled) {
      throw StateError('Living Intelligence is disabled.');
    }
    return cloudConsent.issue(
      purposeId: purpose.name,
      contextCapsuleId: contextCapsuleId,
      permittedDataLabels: permittedDataLabels,
      context: context,
      ttl: ttl,
      now: now,
    );
  }

  NeuraFreshApprovalIssue issueFreshApprovalLease({
    required String leaseId,
    required String actionFingerprint,
    required String capabilityId,
    required String contextCapsuleId,
    required String deviceId,
    required NeuraSafetyContext context,
    required bool explicitApproval,
    required bool capabilityRegistered,
    required bool criticalCapability,
    required bool involvesMoneyMovement,
    Duration lifetime = const Duration(seconds: 90),
    DateTime? now,
  }) {
    if (!_enabled) {
      throw StateError('Living Intelligence is disabled.');
    }
    return freshApprovalLeases.issue(
      leaseId: leaseId,
      scope: NeuraFreshApprovalScope(
        actionFingerprint: actionFingerprint,
        capabilityId: capabilityId,
        capsuleId: contextCapsuleId,
        deviceId: deviceId,
      ),
      issuedAt: now ?? DateTime.now(),
      lifetime: lifetime,
      safetyContext: context,
      explicitApproval: explicitApproval,
      capabilityRegistered: capabilityRegistered,
      criticalCapability: criticalCapability,
      involvesMoneyMovement: involvesMoneyMovement,
      safeModeActive: safetyPolicy.safeModeActive,
    );
  }

  NeuraModelRequest buildGuidedModelRequest({
    required NeuraModelPurpose purpose,
    required String prompt,
    required NeuraSafetyContext safetyContext,
    NeuraAudience audience = NeuraAudience.adult,
    NeuraSupportSignal supportSignal = NeuraSupportSignal.standard,
    NeuraResponseDepth responseDepth = NeuraResponseDepth.balanced,
    String visibleContext = '',
    Iterable<String> permittedDataLabels = const <String>[],
    bool containsPrivateRecords = false,
    String contextCapsuleId = 'personal',
    String? cloudConsentPermitId,
  }) {
    return NeuraModelRequest(
      purpose: purpose,
      prompt: prompt,
      visibleContext: visibleContext,
      permittedDataLabels: permittedDataLabels,
      containsPrivateRecords: containsPrivateRecords,
      contextCapsuleId: contextCapsuleId,
      cloudConsentPermitId: cloudConsentPermitId,
      responseGuidance: responsePolicy.guidanceFor(
        audience: audience,
        supportSignal: supportSignal,
        depth: responseDepth,
        quietMode: presenceEngine.isQuiet,
      ),
      safetyContext: safetyContext,
    );
  }

  Future<void> resetAfterDataWipe() async {
    _enabled = false;
    modelRouter.enabled = false;
    turnCoordinator.cancelActiveTurn();
    cloudConsent.resetAfterDataWipe();
    freshApprovalLeases.resetAfterDataWipe();
    skillHealth.resetAfterDataWipe();
    continuity.resetAfterDataWipe();
    await turnCoordinator.enterQuietMode();
  }
}
