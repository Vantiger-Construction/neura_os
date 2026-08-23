import '../intent_compiler/neura_action_graph.dart';
import 'neura_cognitive_state.dart';

enum NeuraInformationDensity { minimal, compact, standard, detailed }

enum NeuraAutomationDepth {
  suggestOnly,
  localAfterConfirmation,
  approvedLowRisk,
}

class NeuraInterfacePolicy {
  final int maxPrimaryActions;
  final NeuraInformationDensity informationDensity;
  final bool showAdvancedMetrics;
  final bool proactiveRecommendationsAllowed;
  final bool externalEffectsAllowed;
  final NeuraAutomationDepth automationDepth;
  final NeuraApprovalTier minimumApprovalTier;

  const NeuraInterfacePolicy({
    required this.maxPrimaryActions,
    required this.informationDensity,
    required this.showAdvancedMetrics,
    required this.proactiveRecommendationsAllowed,
    required this.externalEffectsAllowed,
    required this.automationDepth,
    required this.minimumApprovalTier,
  });

  factory NeuraInterfacePolicy.forState(
    NeuraCognitiveState state, {
    bool safeMode = false,
  }) {
    if (safeMode || state.mode == NeuraBandwidthMode.recovery) {
      return const NeuraInterfacePolicy(
        maxPrimaryActions: 1,
        informationDensity: NeuraInformationDensity.minimal,
        showAdvancedMetrics: false,
        proactiveRecommendationsAllowed: false,
        externalEffectsAllowed: false,
        automationDepth: NeuraAutomationDepth.suggestOnly,
        minimumApprovalTier: NeuraApprovalTier.elevated,
      );
    }

    return switch (state.mode) {
      NeuraBandwidthMode.recovery => throw StateError(
          'Recovery mode must be handled by the conservative policy branch.',
        ),
      NeuraBandwidthMode.simplified => const NeuraInterfacePolicy(
          maxPrimaryActions: 3,
          informationDensity: NeuraInformationDensity.compact,
          showAdvancedMetrics: false,
          proactiveRecommendationsAllowed: false,
          externalEffectsAllowed: false,
          automationDepth: NeuraAutomationDepth.suggestOnly,
          minimumApprovalTier: NeuraApprovalTier.confirm,
        ),
      NeuraBandwidthMode.balanced => const NeuraInterfacePolicy(
          maxPrimaryActions: 5,
          informationDensity: NeuraInformationDensity.standard,
          showAdvancedMetrics: true,
          proactiveRecommendationsAllowed: true,
          externalEffectsAllowed: true,
          automationDepth: NeuraAutomationDepth.localAfterConfirmation,
          minimumApprovalTier: NeuraApprovalTier.confirm,
        ),
      NeuraBandwidthMode.deepFocus => const NeuraInterfacePolicy(
          maxPrimaryActions: 3,
          informationDensity: NeuraInformationDensity.detailed,
          showAdvancedMetrics: true,
          proactiveRecommendationsAllowed: false,
          externalEffectsAllowed: true,
          automationDepth: NeuraAutomationDepth.approvedLowRisk,
          minimumApprovalTier: NeuraApprovalTier.confirm,
        ),
    };
  }
}
