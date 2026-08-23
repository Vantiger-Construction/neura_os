import '../cognitive/neura_cognitive_state.dart';
import '../intent_compiler/neura_action_graph.dart';

enum NeuraPlanStepStatus { pending, completed, deferred, blocked }

enum NeuraPlanSessionStatus { active, completed, abandoned }

class NeuraPlanStepProgress {
  final NeuraActionStep step;
  final NeuraPlanStepStatus status;
  final bool approvalRecorded;
  final DateTime? updatedAt;

  const NeuraPlanStepProgress({
    required this.step,
    required this.status,
    required this.approvalRecorded,
    this.updatedAt,
  });

  NeuraPlanStepProgress copyWith({
    NeuraPlanStepStatus? status,
    bool? approvalRecorded,
    DateTime? updatedAt,
  }) {
    return NeuraPlanStepProgress(
      step: step,
      status: status ?? this.status,
      approvalRecorded: approvalRecorded ?? this.approvalRecorded,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class NeuraPlanOutcomeReceipt {
  final String sessionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final NeuraBandwidthMode bandwidthMode;
  final NeuraPlanSessionStatus status;
  final int totalLocalSteps;
  final int completedLocalSteps;
  final int deferredLocalSteps;
  final int blockedSteps;
  final int externalSteps;
  final double completionRatio;
  final double perceivedEffort;
  final double satisfaction;
  final int interruptionCount;

  NeuraPlanOutcomeReceipt({
    required this.sessionId,
    required this.startedAt,
    required this.endedAt,
    required this.bandwidthMode,
    required this.status,
    required this.totalLocalSteps,
    required this.completedLocalSteps,
    required this.deferredLocalSteps,
    required this.blockedSteps,
    required this.externalSteps,
    required double completionRatio,
    required double perceivedEffort,
    required double satisfaction,
    required this.interruptionCount,
  }) : completionRatio = completionRatio.clamp(0.0, 1.0).toDouble(),
       perceivedEffort = perceivedEffort.clamp(0.0, 1.0).toDouble(),
       satisfaction = satisfaction.clamp(0.0, 1.0).toDouble();

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'v': 1,
      'session_id': sessionId,
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt.toUtc().toIso8601String(),
      'bandwidth_mode': bandwidthMode.name,
      'status': status.name,
      'total_local_steps': totalLocalSteps,
      'completed_local_steps': completedLocalSteps,
      'deferred_local_steps': deferredLocalSteps,
      'blocked_steps': blockedSteps,
      'external_steps': externalSteps,
      'completion_ratio': completionRatio,
      'perceived_effort': perceivedEffort,
      'satisfaction': satisfaction,
      'interruption_count': interruptionCount,
    };
  }
}

class NeuraAdaptivePlanSession {
  NeuraAdaptivePlanSession._({
    required this.id,
    required this.graph,
    required this.startedAt,
    required Map<String, NeuraPlanStepProgress> progress,
  }) : _progress = progress;

  factory NeuraAdaptivePlanSession.start(
    NeuraActionGraph graph, {
    DateTime? startedAt,
  }) {
    if (graph.steps.isEmpty) {
      throw const FormatException(
        'An Adaptive Intent plan needs at least one step.',
      );
    }

    final progress = <String, NeuraPlanStepProgress>{};
    var safeLocalStepCount = 0;
    for (final step in graph.steps) {
      final id = step.id.trim();
      if (id.isEmpty) {
        throw const FormatException(
          'Adaptive Intent step ids must not be empty.',
        );
      }
      if (id != step.id) {
        throw const FormatException(
          'Adaptive Intent step ids must not contain surrounding whitespace.',
        );
      }
      if (progress.containsKey(id)) {
        throw FormatException('Duplicate Adaptive Intent step id: $id');
      }

      final status = step.blocked
          ? NeuraPlanStepStatus.blocked
          : step.deferred
          ? NeuraPlanStepStatus.deferred
          : NeuraPlanStepStatus.pending;
      progress[id] = NeuraPlanStepProgress(
        step: step,
        status: status,
        approvalRecorded: false,
      );
      if (!step.blocked && !step.effect.isExternal) {
        safeLocalStepCount += 1;
      }
    }

    if (safeLocalStepCount == 0) {
      throw StateError(
        'Adaptive Intent refuses to start a session without a safe local step.',
      );
    }

    final start = (startedAt ?? DateTime.now()).toUtc();
    return NeuraAdaptivePlanSession._(
      id: 'nais-${graph.receipt.id}',
      graph: graph,
      startedAt: start,
      progress: progress,
    );
  }

  final String id;
  final NeuraActionGraph graph;
  final DateTime startedAt;
  final Map<String, NeuraPlanStepProgress> _progress;

  NeuraPlanSessionStatus _status = NeuraPlanSessionStatus.active;
  NeuraPlanOutcomeReceipt? _outcome;

  NeuraPlanSessionStatus get status => _status;
  NeuraPlanOutcomeReceipt? get outcome => _outcome;

  List<NeuraPlanStepProgress> get progress {
    return List<NeuraPlanStepProgress>.unmodifiable(
      graph.steps.map((step) => _progress[step.id]!),
    );
  }

  NeuraPlanStepProgress progressFor(String stepId) {
    final progress = _progress[stepId];
    if (progress == null) {
      throw ArgumentError.value(
        stepId,
        'stepId',
        'is not part of this session',
      );
    }
    return progress;
  }

  void completeStep(
    String stepId, {
    required bool userGesture,
    bool approvalGranted = false,
    bool safeMode = false,
    DateTime? at,
  }) {
    _requireActive();
    _requireUserGesture(userGesture);
    _requireNormalMode(safeMode);

    final current = progressFor(stepId);
    if (current.status == NeuraPlanStepStatus.completed) return;
    if (current.status == NeuraPlanStepStatus.blocked) {
      throw StateError('A policy-blocked step cannot be completed.');
    }
    if (current.status == NeuraPlanStepStatus.deferred) {
      throw StateError('Resume a deferred step before completing it.');
    }
    if (current.step.effect.isExternal) {
      throw StateError(
        'External effects require a separate approved executor result.',
      );
    }
    if (current.step.requiredApproval != NeuraApprovalTier.none &&
        !approvalGranted) {
      throw StateError('This step requires explicit approval.');
    }

    _progress[stepId] = current.copyWith(
      status: NeuraPlanStepStatus.completed,
      approvalRecorded: approvalGranted,
      updatedAt: (at ?? DateTime.now()).toUtc(),
    );
  }

  void deferStep(
    String stepId, {
    required bool userGesture,
    bool safeMode = false,
    DateTime? at,
  }) {
    _requireActive();
    _requireUserGesture(userGesture);
    _requireNormalMode(safeMode);

    final current = progressFor(stepId);
    if (current.status == NeuraPlanStepStatus.deferred) return;
    if (current.status == NeuraPlanStepStatus.completed) {
      throw StateError('A completed step cannot be deferred.');
    }
    if (current.status == NeuraPlanStepStatus.blocked) {
      throw StateError('A policy-blocked step cannot be changed.');
    }

    _progress[stepId] = current.copyWith(
      status: NeuraPlanStepStatus.deferred,
      updatedAt: (at ?? DateTime.now()).toUtc(),
    );
  }

  void resumeStep(
    String stepId, {
    required bool userGesture,
    bool safeMode = false,
    DateTime? at,
  }) {
    _requireActive();
    _requireUserGesture(userGesture);
    _requireNormalMode(safeMode);

    final current = progressFor(stepId);
    if (current.status != NeuraPlanStepStatus.deferred) {
      throw StateError('Only a deferred step can be resumed.');
    }

    _progress[stepId] = current.copyWith(
      status: NeuraPlanStepStatus.pending,
      updatedAt: (at ?? DateTime.now()).toUtc(),
    );
  }

  NeuraPlanOutcomeReceipt finish({
    required bool userGesture,
    bool abandoned = false,
    double perceivedEffort = 0.5,
    double satisfaction = 0.5,
    int interruptionCount = 0,
    DateTime? endedAt,
  }) {
    final existing = _outcome;
    if (existing != null) return existing;

    _requireActive();
    _requireUserGesture(userGesture);

    final local = progress
        .where((item) => !item.step.blocked && !item.step.effect.isExternal)
        .toList(growable: false);
    final pendingLocal = local.where(
      (item) => item.status == NeuraPlanStepStatus.pending,
    );
    final completedLocal = local.where(
      (item) => item.status == NeuraPlanStepStatus.completed,
    );
    final deferredLocal = local.where(
      (item) => item.status == NeuraPlanStepStatus.deferred,
    );

    if (!abandoned && pendingLocal.isNotEmpty) {
      throw StateError(
        'Complete or defer each local step before finishing the session.',
      );
    }
    if (!abandoned && completedLocal.isEmpty) {
      throw StateError(
        'A completed session needs at least one completed step.',
      );
    }

    _status = abandoned
        ? NeuraPlanSessionStatus.abandoned
        : NeuraPlanSessionStatus.completed;
    final completionRatio = local.isEmpty
        ? 0.0
        : completedLocal.length / local.length;
    final receipt = NeuraPlanOutcomeReceipt(
      sessionId: id,
      startedAt: startedAt,
      endedAt: (endedAt ?? DateTime.now()).toUtc(),
      bandwidthMode: graph.receipt.bandwidthMode,
      status: _status,
      totalLocalSteps: local.length,
      completedLocalSteps: completedLocal.length,
      deferredLocalSteps: deferredLocal.length,
      blockedSteps: progress
          .where((item) => item.status == NeuraPlanStepStatus.blocked)
          .length,
      externalSteps: progress
          .where((item) => !item.step.blocked && item.step.effect.isExternal)
          .length,
      completionRatio: completionRatio,
      perceivedEffort: perceivedEffort,
      satisfaction: satisfaction,
      interruptionCount: interruptionCount < 0 ? 0 : interruptionCount,
    );
    _outcome = receipt;
    return receipt;
  }

  void _requireActive() {
    if (_status != NeuraPlanSessionStatus.active) {
      throw StateError('This Adaptive Intent session is already closed.');
    }
  }

  void _requireUserGesture(bool userGesture) {
    if (!userGesture) {
      throw StateError('Plan progress requires a direct user gesture.');
    }
  }

  void _requireNormalMode(bool safeMode) {
    if (safeMode) {
      throw StateError('Safe Mode blocks Adaptive Intent progress changes.');
    }
  }
}
