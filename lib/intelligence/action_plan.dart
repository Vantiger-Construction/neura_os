import 'package:flutter/foundation.dart';

import 'approval_broker.dart';

enum NeuraActionPlanState { ready, awaitingApproval, completed, blocked }

@immutable
class NeuraActionPlanStep {
  const NeuraActionPlanStep({required this.actionId, required this.title});

  final String actionId;
  final String title;
}

/// Coordinates reviewed Action Loom actions without creating new authority.
///
/// The plan never approves or executes an action. It exposes one action at a
/// time, and advances only after Action Loom reports that exact action as
/// executed. Every step therefore retains its own visible, fresh approval.
class NeuraActionPlan extends ChangeNotifier {
  NeuraActionPlan(Iterable<NeuraActionPlanStep> steps)
      : steps = List<NeuraActionPlanStep>.unmodifiable(steps) {
    if (this.steps.isEmpty || this.steps.length > maximumSteps) {
      throw ArgumentError('A safe action plan needs 1–$maximumSteps steps.');
    }
    final ids = <String>{};
    for (final step in this.steps) {
      if (step.actionId.trim().isEmpty ||
          step.title.trim().isEmpty ||
          !ids.add(step.actionId.trim())) {
        throw ArgumentError('Action plan steps need unique ids and titles.');
      }
    }
  }

  static const int maximumSteps = 8;

  final List<NeuraActionPlanStep> steps;
  int _nextIndex = 0;
  String? _blockedReason;

  int get completedStepCount => _nextIndex;
  String? get blockedReason => _blockedReason;
  bool get requiresApprovalForEveryStep => true;

  NeuraActionPlanStep? get nextStep =>
      _nextIndex < steps.length && _blockedReason == null
          ? steps[_nextIndex]
          : null;

  NeuraActionPlanState get state {
    if (_blockedReason != null) return NeuraActionPlanState.blocked;
    if (_nextIndex >= steps.length) return NeuraActionPlanState.completed;
    return NeuraActionPlanState.awaitingApproval;
  }

  /// Records the latest Action Loom snapshot for the current step.
  ///
  /// Intermediate states do not advance. Denied, expired, blocked, or failed
  /// actions stop the plan. A caller must create a new reviewed plan rather
  /// than silently skipping a failed side effect.
  void record(NeuraApprovalAction action) {
    recordOutcome(
      actionId: action.id,
      status: action.status,
      reason: action.denialReason ?? action.policyReason ?? action.failure,
    );
  }

  /// Metadata-only counterpart used by UI adapters that already hold a
  /// broker snapshot. It cannot approve or execute the action.
  void recordOutcome({
    required String actionId,
    required NeuraApprovalStatus status,
    String? reason,
  }) {
    final expected = nextStep;
    if (expected == null) return;
    if (actionId != expected.actionId) {
      throw StateError('Only the current reviewed action may advance a plan.');
    }

    if (status == NeuraApprovalStatus.executed) {
      _nextIndex += 1;
      notifyListeners();
      return;
    }

    if (status == NeuraApprovalStatus.denied ||
        status == NeuraApprovalStatus.expired ||
        status == NeuraApprovalStatus.blocked ||
        status == NeuraApprovalStatus.failed) {
      _blockedReason = reason ?? 'The reviewed action did not complete.';
      notifyListeners();
    }
  }
}
