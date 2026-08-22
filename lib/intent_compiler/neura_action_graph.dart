import '../cognitive/neura_cognitive_state.dart';
import 'neura_intent.dart';

enum NeuraActionEffect {
  localRead,
  localWrite,
  notification,
  calendar,
  externalMessage,
  purchase,
  cloudRequest,
}

extension NeuraActionEffectPolicy on NeuraActionEffect {
  bool get isExternal {
    return switch (this) {
      NeuraActionEffect.localRead || NeuraActionEffect.localWrite => false,
      _ => true,
    };
  }

  String get label {
    return switch (this) {
      NeuraActionEffect.localRead => 'Local read',
      NeuraActionEffect.localWrite => 'Local change',
      NeuraActionEffect.notification => 'Notification',
      NeuraActionEffect.calendar => 'Calendar',
      NeuraActionEffect.externalMessage => 'External message',
      NeuraActionEffect.purchase => 'Purchase',
      NeuraActionEffect.cloudRequest => 'Cloud request',
    };
  }
}

enum NeuraApprovalTier {
  none,
  confirm,
  elevated,
}

NeuraApprovalTier stricterApproval(
  NeuraApprovalTier first,
  NeuraApprovalTier second,
) {
  return first.index >= second.index ? first : second;
}

class NeuraActionStep {
  final String id;
  final String title;
  final String description;
  final NeuraActionEffect effect;
  final NeuraApprovalTier requiredApproval;
  final bool reversible;
  final String? rollbackDescription;
  final int estimatedMinutes;
  final int priority;
  final bool deferred;
  final bool blocked;
  final String? blockReason;
  final bool isWorkRelated;
  final bool containsSensitiveContent;

  const NeuraActionStep({
    required this.id,
    required this.title,
    required this.description,
    required this.effect,
    required this.requiredApproval,
    required this.reversible,
    required this.estimatedMinutes,
    required this.priority,
    this.rollbackDescription,
    this.deferred = false,
    this.blocked = false,
    this.blockReason,
    this.isWorkRelated = false,
    this.containsSensitiveContent = false,
  });

  NeuraActionStep copyWith({
    NeuraApprovalTier? requiredApproval,
    bool? deferred,
    bool? blocked,
    String? blockReason,
  }) {
    return NeuraActionStep(
      id: id,
      title: title,
      description: description,
      effect: effect,
      requiredApproval: requiredApproval ?? this.requiredApproval,
      reversible: reversible,
      rollbackDescription: rollbackDescription,
      estimatedMinutes: estimatedMinutes,
      priority: priority,
      deferred: deferred ?? this.deferred,
      blocked: blocked ?? this.blocked,
      blockReason: blockReason ?? this.blockReason,
      isWorkRelated: isWorkRelated,
      containsSensitiveContent: containsSensitiveContent,
    );
  }
}

class NeuraDecisionReceipt {
  final String id;
  final DateTime createdAt;
  final NeuraBandwidthMode bandwidthMode;
  final double bandwidth;
  final double confidence;
  final int blockedStepCount;
  final int approvalStepCount;
  final List<String> reasons;

  NeuraDecisionReceipt({
    required this.id,
    required this.createdAt,
    required this.bandwidthMode,
    required this.bandwidth,
    required this.confidence,
    required this.blockedStepCount,
    required this.approvalStepCount,
    List<String> reasons = const <String>[],
  }) : reasons = List<String>.unmodifiable(reasons);
}

class NeuraActionGraph {
  final String outcome;
  final NeuraIntent intent;
  final List<NeuraActionStep> steps;
  final NeuraDecisionReceipt receipt;

  NeuraActionGraph({
    required this.outcome,
    required this.intent,
    required List<NeuraActionStep> steps,
    required this.receipt,
  }) : steps = List<NeuraActionStep>.unmodifiable(steps);

  List<NeuraActionStep> get primarySteps {
    return steps
        .where((step) => !step.deferred && !step.blocked)
        .toList(growable: false);
  }

  List<NeuraActionStep> get deferredSteps {
    return steps.where((step) => step.deferred).toList(growable: false);
  }

  List<NeuraActionStep> get blockedSteps {
    return steps.where((step) => step.blocked).toList(growable: false);
  }

  bool get requiresApproval {
    return steps.any(
      (step) =>
          !step.blocked &&
          step.requiredApproval != NeuraApprovalTier.none,
    );
  }
}
