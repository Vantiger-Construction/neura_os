import '../intelligence/capability_registry.dart';

enum NeuraContextCapsuleKind {
  personal,
  work,
  care,
  kids,
  privateVault,
  guest,
}

enum NeuraCapsuleDataCategory {
  generalPreferences,
  workPlans,
  carePlans,
  kidsContent,
  privateRecords,
  financialData,
  localQuests,
}

class NeuraContextCapsule {
  NeuraContextCapsule({
    required this.kind,
    required this.partitionId,
    required Iterable<NeuraCapsuleDataCategory> dataCategories,
    required Iterable<String> allowedCapabilities,
    this.cloudInferenceAllowed = false,
    this.retention = const Duration(days: 30),
  })  : dataCategories =
            Set<NeuraCapsuleDataCategory>.unmodifiable(dataCategories),
        allowedCapabilities = Set<String>.unmodifiable(allowedCapabilities);

  final NeuraContextCapsuleKind kind;
  final String partitionId;
  final Set<NeuraCapsuleDataCategory> dataCategories;
  final Set<String> allowedCapabilities;
  final bool cloudInferenceAllowed;
  final Duration retention;
}

class NeuraCapsuleTransferDecision {
  const NeuraCapsuleTransferDecision({
    required this.allowed,
    required this.reason,
  });

  final bool allowed;
  final String reason;
}

/// Registry for isolated operating contexts.
///
/// The registry stores policy metadata only. Capsule memory must use
/// [partitionId] as its encrypted storage namespace.
class NeuraContextCapsuleRegistry {
  NeuraContextCapsuleRegistry({
    Iterable<NeuraContextCapsule>? capsules,
  }) : _capsules = {
          for (final capsule in capsules ?? defaults()) capsule.kind: capsule,
        };

  final Map<NeuraContextCapsuleKind, NeuraContextCapsule> _capsules;

  NeuraContextCapsule capsule(NeuraContextCapsuleKind kind) {
    final result = _capsules[kind];
    if (result == null) {
      throw StateError('The requested context capsule is not registered.');
    }
    return result;
  }

  List<NeuraContextCapsule> get all =>
      List<NeuraContextCapsule>.unmodifiable(_capsules.values);

  NeuraCapsuleTransferDecision evaluateTransfer({
    required NeuraContextCapsuleKind source,
    required NeuraContextCapsuleKind destination,
    required NeuraCapsuleDataCategory category,
    required bool directUserGesture,
    required bool freshApproval,
  }) {
    if (source == destination) {
      return const NeuraCapsuleTransferDecision(
        allowed: true,
        reason: 'The data remains inside the same capsule.',
      );
    }

    if (!directUserGesture || !freshApproval) {
      return const NeuraCapsuleTransferDecision(
        allowed: false,
        reason: 'Cross-capsule transfer requires a direct, fresh approval.',
      );
    }

    final sourceCapsule = capsule(source);
    final destinationCapsule = capsule(destination);

    if (!sourceCapsule.dataCategories.contains(category) ||
        !destinationCapsule.dataCategories.contains(category)) {
      return const NeuraCapsuleTransferDecision(
        allowed: false,
        reason: 'The data category is not permitted in both capsules.',
      );
    }

    if (destination == NeuraContextCapsuleKind.kids &&
        (category == NeuraCapsuleDataCategory.privateRecords ||
            category == NeuraCapsuleDataCategory.financialData ||
            category == NeuraCapsuleDataCategory.workPlans)) {
      return const NeuraCapsuleTransferDecision(
        allowed: false,
        reason: 'Kids context cannot receive adult private or financial data.',
      );
    }

    if (destination == NeuraContextCapsuleKind.guest &&
        category != NeuraCapsuleDataCategory.generalPreferences) {
      return const NeuraCapsuleTransferDecision(
        allowed: false,
        reason: 'Guest context accepts only temporary general preferences.',
      );
    }

    return const NeuraCapsuleTransferDecision(
      allowed: true,
      reason: 'The approved transfer is permitted by both capsule policies.',
    );
  }

  static List<NeuraContextCapsule> defaults() {
    const suggestion = NeuraCapabilityRegistry.surfaceSuggestion;
    const openModule = NeuraCapabilityRegistry.openAppModule;
    const localPlan = NeuraCapabilityRegistry.changeLocalPlan;

    return [
      NeuraContextCapsule(
        kind: NeuraContextCapsuleKind.personal,
        partitionId: 'capsule.personal.v1',
        dataCategories: const {
          NeuraCapsuleDataCategory.generalPreferences,
          NeuraCapsuleDataCategory.carePlans,
          NeuraCapsuleDataCategory.privateRecords,
          NeuraCapsuleDataCategory.financialData,
          NeuraCapsuleDataCategory.localQuests,
        },
        allowedCapabilities: const {
          suggestion,
          openModule,
          localPlan,
        },
      ),
      NeuraContextCapsule(
        kind: NeuraContextCapsuleKind.work,
        partitionId: 'capsule.work.v1',
        dataCategories: const {
          NeuraCapsuleDataCategory.generalPreferences,
          NeuraCapsuleDataCategory.workPlans,
          NeuraCapsuleDataCategory.localQuests,
        },
        allowedCapabilities: const {
          suggestion,
          openModule,
          localPlan,
        },
      ),
      NeuraContextCapsule(
        kind: NeuraContextCapsuleKind.care,
        partitionId: 'capsule.care.v1',
        dataCategories: const {
          NeuraCapsuleDataCategory.generalPreferences,
          NeuraCapsuleDataCategory.carePlans,
          NeuraCapsuleDataCategory.localQuests,
        },
        allowedCapabilities: const {
          suggestion,
          openModule,
          localPlan,
        },
      ),
      NeuraContextCapsule(
        kind: NeuraContextCapsuleKind.kids,
        partitionId: 'capsule.kids.v1',
        dataCategories: const {
          NeuraCapsuleDataCategory.generalPreferences,
          NeuraCapsuleDataCategory.kidsContent,
          NeuraCapsuleDataCategory.localQuests,
        },
        allowedCapabilities: const {
          suggestion,
          openModule,
        },
        retention: const Duration(days: 7),
      ),
      NeuraContextCapsule(
        kind: NeuraContextCapsuleKind.privateVault,
        partitionId: 'capsule.private_vault.v1',
        dataCategories: const {
          NeuraCapsuleDataCategory.privateRecords,
        },
        allowedCapabilities: const {
          suggestion,
          openModule,
        },
        retention: const Duration(days: 3650),
      ),
      NeuraContextCapsule(
        kind: NeuraContextCapsuleKind.guest,
        partitionId: 'capsule.guest.v1',
        dataCategories: const {
          NeuraCapsuleDataCategory.generalPreferences,
        },
        allowedCapabilities: const {
          suggestion,
          openModule,
        },
        retention: const Duration(hours: 8),
      ),
    ];
  }
}
