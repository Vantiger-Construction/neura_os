import '../intent_compiler/neura_action_graph.dart';

class NeuraConstitutionDecision {
  final bool allowed;
  final String reason;
  final NeuraApprovalTier requiredApproval;

  const NeuraConstitutionDecision({
    required this.allowed,
    required this.reason,
    required this.requiredApproval,
  });
}

class NeuraPersonalConstitution {
  final bool allowCloudAi;
  final bool allowExternalMessages;
  final bool allowPurchases;
  final bool allowCalendarWrites;
  final bool keepSensitiveContentLocal;
  final bool requireExternalPreview;
  final int workHoursStart;
  final int workHoursEnd;

  const NeuraPersonalConstitution({
    this.allowCloudAi = false,
    this.allowExternalMessages = false,
    this.allowPurchases = false,
    this.allowCalendarWrites = true,
    this.keepSensitiveContentLocal = true,
    this.requireExternalPreview = true,
    this.workHoursStart = 7,
    this.workHoursEnd = 20,
  });

  NeuraPersonalConstitution normalized() {
    return NeuraPersonalConstitution(
      allowCloudAi: allowCloudAi,
      allowExternalMessages: allowExternalMessages,
      allowPurchases: allowPurchases,
      allowCalendarWrites: allowCalendarWrites,
      keepSensitiveContentLocal: keepSensitiveContentLocal,
      requireExternalPreview: requireExternalPreview,
      workHoursStart: workHoursStart.clamp(0, 23).toInt(),
      workHoursEnd: workHoursEnd.clamp(0, 23).toInt(),
    );
  }

  NeuraPersonalConstitution copyWith({
    bool? allowCloudAi,
    bool? allowExternalMessages,
    bool? allowPurchases,
    bool? allowCalendarWrites,
    bool? keepSensitiveContentLocal,
    bool? requireExternalPreview,
    int? workHoursStart,
    int? workHoursEnd,
  }) {
    return NeuraPersonalConstitution(
      allowCloudAi: allowCloudAi ?? this.allowCloudAi,
      allowExternalMessages:
          allowExternalMessages ?? this.allowExternalMessages,
      allowPurchases: allowPurchases ?? this.allowPurchases,
      allowCalendarWrites: allowCalendarWrites ?? this.allowCalendarWrites,
      keepSensitiveContentLocal:
          keepSensitiveContentLocal ?? this.keepSensitiveContentLocal,
      requireExternalPreview:
          requireExternalPreview ?? this.requireExternalPreview,
      workHoursStart: workHoursStart ?? this.workHoursStart,
      workHoursEnd: workHoursEnd ?? this.workHoursEnd,
    ).normalized();
  }

  NeuraConstitutionDecision evaluate(
    NeuraActionStep action, {
    required DateTime at,
    bool safeMode = false,
  }) {
    if (safeMode && action.effect.isExternal) {
      return const NeuraConstitutionDecision(
        allowed: false,
        reason: 'Safe Mode blocks every external effect.',
        requiredApproval: NeuraApprovalTier.elevated,
      );
    }

    if (action.containsSensitiveContent &&
        keepSensitiveContentLocal &&
        action.effect == NeuraActionEffect.cloudRequest) {
      return const NeuraConstitutionDecision(
        allowed: false,
        reason:
            'Sensitive content is constitutionally restricted to local use.',
        requiredApproval: NeuraApprovalTier.elevated,
      );
    }

    if (action.effect == NeuraActionEffect.cloudRequest && !allowCloudAi) {
      return const NeuraConstitutionDecision(
        allowed: false,
        reason: 'Cloud AI is disabled by the personal constitution.',
        requiredApproval: NeuraApprovalTier.elevated,
      );
    }

    if (action.effect == NeuraActionEffect.externalMessage &&
        !allowExternalMessages) {
      return const NeuraConstitutionDecision(
        allowed: false,
        reason: 'External messages are disabled by the personal constitution.',
        requiredApproval: NeuraApprovalTier.elevated,
      );
    }

    if (action.effect == NeuraActionEffect.purchase && !allowPurchases) {
      return const NeuraConstitutionDecision(
        allowed: false,
        reason: 'Purchases are disabled by the personal constitution.',
        requiredApproval: NeuraApprovalTier.elevated,
      );
    }

    if (action.effect == NeuraActionEffect.calendar && !allowCalendarWrites) {
      return const NeuraConstitutionDecision(
        allowed: false,
        reason: 'Calendar changes are disabled by the personal constitution.',
        requiredApproval: NeuraApprovalTier.confirm,
      );
    }

    if (action.isWorkRelated &&
        action.effect.isExternal &&
        !_insideWorkHours(at.hour)) {
      return const NeuraConstitutionDecision(
        allowed: false,
        reason:
            'External work actions are blocked outside configured work hours.',
        requiredApproval: NeuraApprovalTier.elevated,
      );
    }

    final approval = switch (action.effect) {
      NeuraActionEffect.localRead => NeuraApprovalTier.none,
      NeuraActionEffect.localWrite ||
      NeuraActionEffect.notification ||
      NeuraActionEffect.calendar =>
        NeuraApprovalTier.confirm,
      NeuraActionEffect.externalMessage => requireExternalPreview
          ? NeuraApprovalTier.elevated
          : NeuraApprovalTier.confirm,
      NeuraActionEffect.purchase ||
      NeuraActionEffect.cloudRequest =>
        NeuraApprovalTier.elevated,
    };

    return NeuraConstitutionDecision(
      allowed: true,
      reason: approval == NeuraApprovalTier.none
          ? 'This step is a local, read-only operation.'
          : 'This step is allowed only with the required user approval.',
      requiredApproval: approval,
    );
  }

  bool _insideWorkHours(int hour) {
    if (workHoursStart == workHoursEnd) return true;
    if (workHoursStart < workHoursEnd) {
      return hour >= workHoursStart && hour < workHoursEnd;
    }
    return hour >= workHoursStart || hour < workHoursEnd;
  }
}
