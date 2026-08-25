import '../intelligence/capability_registry.dart';
import 'android_intelligence_bridge.dart';
import 'context_capsules.dart';
import 'device_continuity.dart';
import 'future_paths_simulator.dart';
import 'neura_safety_policy.dart';
import 'presence_engine.dart';
import 'private_neural_core.dart';
import 'reflex_safety_layer.dart';
import 'self_healing_runtime.dart';
import 'signed_skill_capsules.dart';
import 'trust_lens.dart';

class NeuraLivingIntelligenceStatus {
  const NeuraLivingIntelligenceStatus({
    required this.enabled,
    required this.safeModeBlocked,
    required this.localModelBackends,
    required this.pairedDevices,
  });

  final bool enabled;
  final bool safeModeBlocked;
  final int localModelBackends;
  final int pairedDevices;
}

/// Coordination facade for Neura 1.5.
///
/// The facade is disabled by default. It exposes policy and preparation
/// services only; Action Loom remains the sole authority for real mutations.
class NeuraLivingIntelligenceRuntime {
  NeuraLivingIntelligenceRuntime({
    required this.safetyPolicy,
    required this.modelRouter,
    required this.reflexLayer,
    required this.trustLens,
    required this.contextCapsules,
    required this.skillValidator,
    required this.skillHealth,
    required this.presenceEngine,
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

    return NeuraLivingIntelligenceRuntime(
      safetyPolicy: safetyPolicy,
      modelRouter: NeuraLocalModelRouter(
        safetyPolicy: safetyPolicy,
        backends: modelBackends,
      ),
      reflexLayer: NeuraReflexSafetyLayer(
        bindings: reflexBindings,
      ),
      trustLens: const NeuraTrustLens(),
      contextCapsules: NeuraContextCapsuleRegistry(),
      skillValidator: NeuraSignedSkillValidator(
        signatureVerifier: signatureVerifier,
      ),
      skillHealth: NeuraSkillHealthRegistry(),
      presenceEngine: NeuraPresenceEngine(
        bindings: presenceBindings,
      ),
      futurePaths: const NeuraFuturePathsSimulator(),
      selfHealing: NeuraSelfHealingRuntime(),
      androidBridge: const NeuraAndroidIntelligenceBridge(),
      continuity: NeuraDeviceContinuityRegistry(),
    );
  }

  final NeuraLivingSafetyPolicy safetyPolicy;
  final NeuraLocalModelRouter modelRouter;
  final NeuraReflexSafetyLayer reflexLayer;
  final NeuraTrustLens trustLens;
  final NeuraContextCapsuleRegistry contextCapsules;
  final NeuraSignedSkillValidator skillValidator;
  final NeuraSkillHealthRegistry skillHealth;
  final NeuraPresenceEngine presenceEngine;
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
      localModelBackends: modelRouter.backends
          .where((backend) => backend.runsLocally)
          .length,
      pairedDevices: continuity.devices.length,
    );
  }

  void setEnabled(
    bool value, {
    required NeuraSafetyContext context,
  }) {
    if (value &&
        (safetyPolicy.safeModeActive || context.recoveryMode)) {
      throw StateError(
        'Living Intelligence cannot be enabled in Safe Mode or Recovery mode.',
      );
    }

    _enabled = value;
    modelRouter.enabled = value;
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

  Future<void> resetAfterDataWipe() async {
    _enabled = false;
    modelRouter.enabled = false;
    skillHealth.resetAfterDataWipe();
    continuity.resetAfterDataWipe();
    await presenceEngine.enterQuietMode();
  }
}
