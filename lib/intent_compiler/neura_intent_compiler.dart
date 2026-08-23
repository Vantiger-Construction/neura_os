import '../cognitive/neura_cognitive_state.dart';
import '../cognitive/neura_interface_policy.dart';
import '../constitution/neura_personal_constitution.dart';
import 'neura_action_graph.dart';
import 'neura_intent.dart';

class NeuraIntentCompiler {
  final NeuraIntentClassifier classifier;

  const NeuraIntentCompiler({this.classifier = const NeuraIntentClassifier()});

  NeuraActionGraph compile({
    required String outcome,
    required NeuraCognitiveState cognitiveState,
    required NeuraInterfacePolicy interfacePolicy,
    required NeuraPersonalConstitution constitution,
    bool safeMode = false,
    DateTime? now,
  }) {
    final decisionAt = now ?? DateTime.now();
    final createdAt = decisionAt.toUtc();
    final intent = classifier.classify(outcome);
    final template = _templateFor(intent);
    final evaluated = <NeuraActionStep>[];

    for (var index = 0; index < template.length; index += 1) {
      final step = template[index];
      final constitutionDecision = constitution.evaluate(
        step,
        at: decisionAt,
        safeMode: safeMode,
      );

      var blocked = !constitutionDecision.allowed;
      var blockReason = constitutionDecision.allowed
          ? null
          : constitutionDecision.reason;

      if (!blocked &&
          step.effect.isExternal &&
          !interfacePolicy.externalEffectsAllowed) {
        blocked = true;
        blockReason =
            '${cognitiveState.mode.label} mode blocks external effects until '
            'the user returns to a higher-bandwidth state.';
      }

      final minimumApproval = stricterApproval(
        interfacePolicy.minimumApprovalTier,
        constitutionDecision.requiredApproval,
      );
      final approval = step.effect == NeuraActionEffect.localRead
          ? NeuraApprovalTier.none
          : stricterApproval(step.requiredApproval, minimumApproval);

      evaluated.add(
        step.copyWith(
          requiredApproval: approval,
          deferred: !blocked && index >= interfacePolicy.maxPrimaryActions,
          blocked: blocked,
          blockReason: blockReason,
        ),
      );
    }

    final blockedCount = evaluated.where((step) => step.blocked).length;
    final approvalCount = evaluated
        .where(
          (step) =>
              !step.blocked && step.requiredApproval != NeuraApprovalTier.none,
        )
        .length;
    final reasons = <String>[
      ...cognitiveState.reasons,
      'The interface exposes at most '
          '${interfacePolicy.maxPrimaryActions} primary action'
          '${interfacePolicy.maxPrimaryActions == 1 ? '' : 's'} in this mode.',
      if (blockedCount > 0)
        '$blockedCount step${blockedCount == 1 ? '' : 's'} failed policy checks '
            'and will not execute.',
      'This prototype only compiles plans; it never executes an external effect.',
    ];

    return NeuraActionGraph(
      outcome: intent.rawOutcome,
      intent: intent,
      steps: evaluated,
      receipt: NeuraDecisionReceipt(
        id: 'nai-${createdAt.microsecondsSinceEpoch}-${intent.kind.name}',
        createdAt: createdAt,
        bandwidthMode: cognitiveState.mode,
        bandwidth: cognitiveState.availableBandwidth,
        confidence: cognitiveState.confidence,
        blockedStepCount: blockedCount,
        approvalStepCount: approvalCount,
        reasons: reasons,
      ),
    );
  }

  List<NeuraActionStep> _templateFor(NeuraIntent intent) {
    return switch (intent.kind) {
      NeuraIntentKind.recovery => _recoverySteps(intent),
      NeuraIntentKind.weeklyPlan => _weeklyPlanSteps(intent),
      NeuraIntentKind.deepFocus => _focusSteps(intent),
      NeuraIntentKind.organize => _organizeSteps(intent),
      NeuraIntentKind.communicate => _communicationSteps(intent),
      NeuraIntentKind.purchase => _purchaseSteps(intent),
      NeuraIntentKind.research => _researchSteps(intent),
      NeuraIntentKind.general => _generalSteps(intent),
    };
  }

  List<NeuraActionStep> _recoverySteps(NeuraIntent intent) {
    return <NeuraActionStep>[
      _step(
        id: 'recovery-ground',
        title: 'Choose one stabilizing action',
        description:
            'Pick water, breathing, a short walk, or a two-minute reset.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 2,
        priority: 100,
        intent: intent,
      ),
      _step(
        id: 'recovery-quiet',
        title: 'Draft a twenty-minute quiet period',
        description:
            'Prepare a reversible pause for noncritical Neura reminders.',
        effect: NeuraActionEffect.notification,
        approval: NeuraApprovalTier.confirm,
        minutes: 1,
        priority: 90,
        intent: intent,
        rollback: 'Restore the previous reminder state.',
      ),
      _step(
        id: 'recovery-park',
        title: 'Park everything that can wait',
        description: 'Save a local list without asking you to solve it now.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 3,
        priority: 80,
        intent: intent,
      ),
    ];
  }

  List<NeuraActionStep> _weeklyPlanSteps(NeuraIntent intent) {
    return <NeuraActionStep>[
      _step(
        id: 'week-review',
        title: 'Review local commitments',
        description:
            'Collect deadlines and unfinished items without changing them.',
        effect: NeuraActionEffect.localRead,
        approval: NeuraApprovalTier.none,
        minutes: 3,
        priority: 100,
        intent: intent,
      ),
      _step(
        id: 'week-three',
        title: 'Choose three outcomes',
        description: 'Reduce the week to three results that matter most.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 4,
        priority: 90,
        intent: intent,
      ),
      _step(
        id: 'week-blocks',
        title: 'Draft focus blocks',
        description:
            'Prepare calendar blocks but do not add them without approval.',
        effect: NeuraActionEffect.calendar,
        approval: NeuraApprovalTier.confirm,
        minutes: 4,
        priority: 80,
        intent: intent,
        rollback: 'Remove the drafted focus blocks.',
      ),
      _step(
        id: 'week-review-point',
        title: 'Add a local review checkpoint',
        description: 'Create a local reminder to reassess the plan midweek.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 1,
        priority: 70,
        intent: intent,
      ),
    ];
  }

  List<NeuraActionStep> _focusSteps(NeuraIntent intent) {
    return <NeuraActionStep>[
      _step(
        id: 'focus-finish-line',
        title: 'Name the finish line',
        description:
            'Turn the outcome into one observable completion condition.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 2,
        priority: 100,
        intent: intent,
      ),
      _step(
        id: 'focus-protect',
        title: 'Draft a protected focus block',
        description:
            'Prepare a reversible notification pause for the work block.',
        effect: NeuraActionEffect.notification,
        approval: NeuraApprovalTier.confirm,
        minutes: 1,
        priority: 90,
        intent: intent,
        rollback: 'Restore notification delivery immediately.',
      ),
      _step(
        id: 'focus-queue',
        title: 'Create a distraction queue',
        description:
            'Capture unrelated thoughts locally without switching tasks.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 1,
        priority: 80,
        intent: intent,
      ),
    ];
  }

  List<NeuraActionStep> _organizeSteps(NeuraIntent intent) {
    return <NeuraActionStep>[
      _step(
        id: 'organize-gather',
        title: 'Gather the local items',
        description: 'Read the relevant local list without modifying it.',
        effect: NeuraActionEffect.localRead,
        approval: NeuraApprovalTier.none,
        minutes: 3,
        priority: 100,
        intent: intent,
      ),
      _step(
        id: 'organize-groups',
        title: 'Group by urgency and effort',
        description: 'Create a reversible local classification.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 4,
        priority: 90,
        intent: intent,
      ),
      _step(
        id: 'organize-next',
        title: 'Choose the next physical action',
        description:
            'Select one small action instead of exposing the full backlog.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 2,
        priority: 80,
        intent: intent,
      ),
    ];
  }

  List<NeuraActionStep> _communicationSteps(NeuraIntent intent) {
    return <NeuraActionStep>[
      _step(
        id: 'message-draft',
        title: 'Draft the message locally',
        description: 'Prepare text for review without contacting anyone.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 4,
        priority: 100,
        intent: intent,
      ),
      _step(
        id: 'message-review',
        title: 'Review recipient, tone, and content',
        description: 'Require an explicit preview before any external send.',
        effect: NeuraActionEffect.localRead,
        approval: NeuraApprovalTier.none,
        minutes: 2,
        priority: 90,
        intent: intent,
      ),
      _step(
        id: 'message-send',
        title: 'Send only after elevated approval',
        description: 'Contact the recipient using the approved final text.',
        effect: NeuraActionEffect.externalMessage,
        approval: NeuraApprovalTier.elevated,
        minutes: 1,
        priority: 80,
        intent: intent,
      ),
    ];
  }

  List<NeuraActionStep> _purchaseSteps(NeuraIntent intent) {
    return <NeuraActionStep>[
      _step(
        id: 'purchase-need',
        title: 'Clarify the need and limit',
        description: 'Record the requirement and maximum budget locally.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 3,
        priority: 100,
        intent: intent,
      ),
      _step(
        id: 'purchase-options',
        title: 'Compare options without buying',
        description: 'Prepare comparison criteria before any transaction.',
        effect: NeuraActionEffect.cloudRequest,
        approval: NeuraApprovalTier.elevated,
        minutes: 8,
        priority: 90,
        intent: intent,
      ),
      _step(
        id: 'purchase-complete',
        title: 'Complete the purchase',
        description:
            'A transaction can occur only after fresh elevated approval.',
        effect: NeuraActionEffect.purchase,
        approval: NeuraApprovalTier.elevated,
        minutes: 2,
        priority: 80,
        intent: intent,
      ),
    ];
  }

  List<NeuraActionStep> _researchSteps(NeuraIntent intent) {
    return <NeuraActionStep>[
      _step(
        id: 'research-question',
        title: 'Define the decision question',
        description: 'Write a focused local question and success criteria.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 2,
        priority: 100,
        intent: intent,
      ),
      _step(
        id: 'research-cloud',
        title: 'Request outside information',
        description:
            'Use cloud research only when the constitution permits it.',
        effect: NeuraActionEffect.cloudRequest,
        approval: NeuraApprovalTier.elevated,
        minutes: 8,
        priority: 90,
        intent: intent,
      ),
      _step(
        id: 'research-summary',
        title: 'Save an evidence summary locally',
        description: 'Record conclusions, uncertainty, and the next decision.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 4,
        priority: 80,
        intent: intent,
      ),
    ];
  }

  List<NeuraActionStep> _generalSteps(NeuraIntent intent) {
    return <NeuraActionStep>[
      _step(
        id: 'general-outcome',
        title: 'Define what done looks like',
        description: 'Turn the request into one observable outcome.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 2,
        priority: 100,
        intent: intent,
      ),
      _step(
        id: 'general-constraints',
        title: 'Identify local constraints',
        description:
            'Review time, energy, dependencies, and safety boundaries.',
        effect: NeuraActionEffect.localRead,
        approval: NeuraApprovalTier.none,
        minutes: 3,
        priority: 90,
        intent: intent,
      ),
      _step(
        id: 'general-next',
        title: 'Choose one reversible next step',
        description:
            'Start with the smallest action that creates useful evidence.',
        effect: NeuraActionEffect.localWrite,
        approval: NeuraApprovalTier.confirm,
        minutes: 3,
        priority: 80,
        intent: intent,
      ),
    ];
  }

  NeuraActionStep _step({
    required String id,
    required String title,
    required String description,
    required NeuraActionEffect effect,
    required NeuraApprovalTier approval,
    required int minutes,
    required int priority,
    required NeuraIntent intent,
    String? rollback,
  }) {
    return NeuraActionStep(
      id: id,
      title: title,
      description: description,
      effect: effect,
      requiredApproval: approval,
      reversible: effect != NeuraActionEffect.purchase,
      rollbackDescription: rollback,
      estimatedMinutes: minutes,
      priority: priority,
      isWorkRelated: intent.isWorkRelated,
      containsSensitiveContent: intent.containsSensitiveContent,
    );
  }
}
