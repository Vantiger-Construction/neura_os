import 'dart:async';

import 'capability_registry.dart';
import 'consent_ledger.dart';
import 'models.dart';

typedef NeuraApprovalClock = DateTime Function();

typedef NeuraApprovalIdFactory = String Function(
  NeuraIntelligenceCandidate candidate,
  DateTime now,
);

typedef NeuraApprovalRevalidator = FutureOr<NeuraPolicyVerdict> Function(
  NeuraApprovalPolicyContext context,
);

enum NeuraApprovalStatus {
  pendingApproval,
  approved,
  policyHeld,
  denied,
  executing,
  executed,
  undoing,
  undone,
  expired,
  blocked,
  failed,
}

enum NeuraApprovalPhase { submit, execute, undo }

class NeuraPolicyVerdict {
  const NeuraPolicyVerdict.allow()
      : allowed = true,
        reason = null;

  const NeuraPolicyVerdict.deny(this.reason) : allowed = false;

  final bool allowed;
  final String? reason;
}

class NeuraApprovalPolicyContext {
  const NeuraApprovalPolicyContext({
    required this.phase,
    required this.action,
    required this.capability,
    required this.now,
    required this.safeMode,
    required this.automatic,
  });

  final NeuraApprovalPhase phase;
  final NeuraApprovalAction action;
  final NeuraCapabilityDefinition capability;
  final DateTime now;
  final bool safeMode;
  final bool automatic;
}

class NeuraCapabilityInvocation {
  const NeuraCapabilityInvocation({
    required this.actionId,
    required this.candidate,
    required this.receipt,
    required this.capability,
    required this.invokedAt,
    required this.automatic,
  });

  final String actionId;
  final NeuraIntelligenceCandidate candidate;
  final NeuraDecisionReceipt receipt;
  final NeuraCapabilityDefinition capability;
  final DateTime invokedAt;
  final bool automatic;
}

class NeuraCapabilityExecutionResult {
  const NeuraCapabilityExecutionResult({this.value, this.undoToken});

  final Object? value;
  final Object? undoToken;
}

/// An undo request that is safe to retry later but cannot be applied now.
class NeuraUndoUnavailableException implements Exception {
  const NeuraUndoUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class NeuraCapabilityExecutor {
  Future<NeuraCapabilityExecutionResult> execute(
    NeuraCapabilityInvocation invocation,
  );

  Future<void> undo(
    NeuraCapabilityInvocation invocation,
    NeuraCapabilityExecutionResult result,
  );
}

class NeuraApprovalAction {
  const NeuraApprovalAction({
    required this.id,
    required this.candidate,
    required this.receipt,
    required this.capability,
    required this.status,
    required this.submittedAt,
    required this.explicitUserApproval,
    this.reviewedAt,
    this.executedAt,
    this.undoneAt,
    this.executionResult,
    this.denialReason,
    this.policyReason,
    this.failure,
  });

  final String id;
  final NeuraIntelligenceCandidate candidate;
  final NeuraDecisionReceipt receipt;
  final NeuraCapabilityDefinition capability;
  final NeuraApprovalStatus status;
  final DateTime submittedAt;
  final bool explicitUserApproval;
  final DateTime? reviewedAt;
  final DateTime? executedAt;
  final DateTime? undoneAt;
  final NeuraCapabilityExecutionResult? executionResult;
  final String? denialReason;
  final String? policyReason;
  final String? failure;

  DateTime get expiresAt => candidate.expiresAt;

  bool get isTerminal =>
      status == NeuraApprovalStatus.denied ||
      status == NeuraApprovalStatus.undone ||
      status == NeuraApprovalStatus.expired ||
      status == NeuraApprovalStatus.blocked ||
      status == NeuraApprovalStatus.failed;
}

/// The last safety boundary between an intelligence suggestion and a side
/// effect.
///
/// Submission is idempotent by candidate id. Execution and undo are also
/// idempotent, including concurrent calls. Elevated capabilities always need
/// a fresh approval on their own action and can never use auto-execution.
class NeuraApprovalBroker {
  NeuraApprovalBroker({
    required Map<String, NeuraCapabilityExecutor> executors,
    NeuraCapabilityRegistry? registry,
    NeuraConsentLedger? consentLedger,
    NeuraApprovalClock? clock,
    NeuraApprovalIdFactory? idFactory,
    bool Function()? safeModeReader,
    NeuraApprovalRevalidator? revalidator,
  })  : registry = registry ?? NeuraCapabilityRegistry(),
        consentLedger = consentLedger ?? NeuraConsentLedger(),
        _executors =
            Map<String, NeuraCapabilityExecutor>.unmodifiable(executors),
        _clock = clock ?? _systemClock,
        _idFactory = idFactory ?? _defaultIdFactory,
        _safeModeReader = safeModeReader ?? _safeModeOff,
        _revalidator = revalidator;

  final NeuraCapabilityRegistry registry;
  final NeuraConsentLedger consentLedger;
  final Map<String, NeuraCapabilityExecutor> _executors;
  final NeuraApprovalClock _clock;
  final NeuraApprovalIdFactory _idFactory;
  final bool Function() _safeModeReader;
  final NeuraApprovalRevalidator? _revalidator;

  final Map<String, _MutableApprovalAction> _actions = {};
  final Map<String, String> _actionIdByCandidate = {};
  final Map<String, NeuraCouncilDecision> _decisionByCandidate = {};
  final Map<String, Future<NeuraApprovalAction>> _submissions = {};
  final Map<String, Future<NeuraApprovalAction>> _executions = {};
  final Map<String, Future<NeuraApprovalAction>> _undos = {};
  bool _suspended = false;

  List<NeuraApprovalAction> get actions {
    if (_suspended) return const [];
    final now = _now();
    final result = _actions.values.map((action) {
      _expireIfNeeded(action, now);
      return action.snapshot();
    }).toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    return List.unmodifiable(result);
  }

  NeuraApprovalAction? find(String actionId) {
    if (_suspended) return null;
    final action = _actions[actionId];
    if (action == null) return null;
    _expireIfNeeded(action, _now());
    return action.snapshot();
  }

  Future<NeuraApprovalAction> submit(
    NeuraCouncilDecision decision, {
    bool autoExecute = false,
  }) {
    _ensureActive();
    final candidateId = decision.candidate.id;
    if (candidateId.trim().isEmpty) {
      throw ArgumentError.value(
        candidateId,
        'candidate.id',
        'Must not be empty.',
      );
    }

    final priorDecision = _decisionByCandidate[candidateId];
    if (priorDecision != null) {
      _assertSameDecision(priorDecision, decision);
    }

    final inFlight = _submissions[candidateId];
    if (inFlight != null) return inFlight;

    final existingId = _actionIdByCandidate[candidateId];
    if (existingId != null) {
      final existing = _requireAction(existingId);
      _assertSameDecision(
        NeuraCouncilDecision(
          candidate: existing.candidate,
          receipt: existing.receipt,
        ),
        decision,
      );
      _expireIfNeeded(existing, _now());
      return Future.value(existing.snapshot());
    }

    _decisionByCandidate[candidateId] = decision;
    final operation = _submitAndClear(
      decision,
      autoExecute: autoExecute,
      candidateId: candidateId,
    );
    _submissions[candidateId] = operation;
    return operation;
  }

  NeuraApprovalAction approve(
    String actionId, {
    Duration sessionDuration = const Duration(hours: 8),
  }) {
    _ensureActive();
    final action = _requireAction(actionId);
    final now = _now();
    _expireIfNeeded(action, now);

    if (action.status == NeuraApprovalStatus.approved ||
        action.status == NeuraApprovalStatus.executed ||
        action.status == NeuraApprovalStatus.undone) {
      return action.snapshot();
    }
    if (action.status == NeuraApprovalStatus.expired ||
        action.status == NeuraApprovalStatus.blocked) {
      return action.snapshot();
    }
    if (action.status != NeuraApprovalStatus.pendingApproval) {
      throw StateError(
        'Action $actionId cannot be approved from ${action.status.name}.',
      );
    }

    final current = registry.resolve(action.candidate.capabilityId);
    final configurationError = _configurationError(action, current);
    if (configurationError != null ||
        current.approvalMode == NeuraApprovalMode.blocked ||
        current.risk == NeuraCapabilityRisk.critical) {
      action
        ..status = NeuraApprovalStatus.blocked
        ..policyReason = configurationError ??
            'This capability is blocked and cannot be approved.';
      return action.snapshot();
    }

    action
      ..status = NeuraApprovalStatus.approved
      ..explicitUserApproval = true
      ..reviewedAt = now
      ..denialReason = null
      ..policyReason = null;

    if (current.approvalMode == NeuraApprovalMode.session &&
        !_isElevated(current)) {
      consentLedger.grantForSession(
        current,
        now: now,
        duration: sessionDuration,
      );
    }
    return action.snapshot();
  }

  NeuraApprovalAction deny(
    String actionId, {
    String reason = 'Denied by the user.',
  }) {
    _ensureActive();
    final action = _requireAction(actionId);
    final now = _now();
    _expireIfNeeded(action, now);

    if (action.status == NeuraApprovalStatus.denied ||
        action.status == NeuraApprovalStatus.expired ||
        action.status == NeuraApprovalStatus.blocked) {
      return action.snapshot();
    }
    if (action.status == NeuraApprovalStatus.policyHeld &&
        action.resumeAfterPolicyHold != NeuraApprovalStatus.approved) {
      throw StateError('Action $actionId has already executed.');
    }
    if (action.status != NeuraApprovalStatus.pendingApproval &&
        action.status != NeuraApprovalStatus.approved &&
        action.status != NeuraApprovalStatus.policyHeld) {
      throw StateError(
        'Action $actionId cannot be denied from ${action.status.name}.',
      );
    }

    action
      ..status = NeuraApprovalStatus.denied
      ..reviewedAt = now
      ..denialReason =
          reason.trim().isEmpty ? 'Denied by the user.' : reason.trim()
      ..policyReason = null
      ..resumeAfterPolicyHold = null;
    return action.snapshot();
  }

  Future<NeuraApprovalAction> execute(String actionId) {
    _ensureActive();
    return _executeOnce(actionId, automatic: false);
  }

  Future<NeuraApprovalAction> undo(String actionId) {
    _ensureActive();
    final inFlight = _undos[actionId];
    if (inFlight != null) return inFlight;

    final operation = _undoAndClear(actionId);
    _undos[actionId] = operation;
    return operation;
  }

  Future<NeuraApprovalAction> _submitAndClear(
    NeuraCouncilDecision decision, {
    required bool autoExecute,
    required String candidateId,
  }) async {
    try {
      return await _submitInternal(decision, autoExecute: autoExecute);
    } catch (_) {
      if (!_actionIdByCandidate.containsKey(candidateId)) {
        _decisionByCandidate.remove(candidateId);
      }
      rethrow;
    } finally {
      final _ = _submissions.remove(candidateId);
    }
  }

  Future<NeuraApprovalAction> _submitInternal(
    NeuraCouncilDecision decision, {
    required bool autoExecute,
  }) async {
    final now = _now();
    final candidate = decision.candidate;
    final receipt = decision.receipt;
    final capability = registry.resolve(candidate.capabilityId);
    final actionId = _idFactory(candidate, now).trim();
    if (actionId.isEmpty) {
      throw StateError('The approval id factory returned an empty id.');
    }
    final collision = _actions[actionId];
    if (collision != null) {
      throw StateError('Approval action id collision: $actionId.');
    }

    final action = _MutableApprovalAction(
      id: actionId,
      candidate: candidate,
      receipt: receipt,
      capability: capability,
      status: NeuraApprovalStatus.pendingApproval,
      submittedAt: now,
    );

    final submissionError = _submissionError(action);
    if (submissionError != null) {
      action
        ..status = NeuraApprovalStatus.blocked
        ..policyReason = submissionError;
    } else if (!now.isBefore(candidate.expiresAt)) {
      action.status = NeuraApprovalStatus.expired;
    } else if (_needsFreshApproval(capability) ||
        receipt.requiresApproval ||
        receipt.outcome == NeuraDecisionOutcome.askApproval ||
        !consentLedger.isGranted(capability, now: now)) {
      action.status = NeuraApprovalStatus.pendingApproval;
    } else {
      action.status = NeuraApprovalStatus.approved;
    }

    _actions[actionId] = action;
    _actionIdByCandidate[candidate.id] = actionId;

    if (action.status == NeuraApprovalStatus.pendingApproval ||
        action.status == NeuraApprovalStatus.approved) {
      final verdict = await _runRevalidator(
        action,
        capability,
        phase: NeuraApprovalPhase.submit,
        automatic: autoExecute,
      );
      if (!verdict.allowed) {
        action
          ..status = NeuraApprovalStatus.blocked
          ..policyReason = _verdictReason(verdict);
      }
    }

    if (autoExecute &&
        action.status == NeuraApprovalStatus.approved &&
        _canAutoExecute(action)) {
      return _executeOnce(actionId, automatic: true);
    }
    return action.snapshot();
  }

  Future<NeuraApprovalAction> _executeOnce(
    String actionId, {
    required bool automatic,
  }) {
    _ensureActive();
    final inFlight = _executions[actionId];
    if (inFlight != null) return inFlight;

    final operation = _executeAndClear(actionId, automatic: automatic);
    _executions[actionId] = operation;
    return operation;
  }

  Future<NeuraApprovalAction> _executeAndClear(
    String actionId, {
    required bool automatic,
  }) async {
    try {
      return await _executeInternal(actionId, automatic: automatic);
    } finally {
      final _ = _executions.remove(actionId);
    }
  }

  Future<NeuraApprovalAction> _executeInternal(
    String actionId, {
    required bool automatic,
  }) async {
    final action = _requireAction(actionId);
    final now = _now();
    _expireIfNeeded(action, now);

    if (action.status == NeuraApprovalStatus.executed ||
        action.status == NeuraApprovalStatus.undone ||
        action.status == NeuraApprovalStatus.failed) {
      return action.snapshot();
    }
    if (action.status == NeuraApprovalStatus.policyHeld) {
      if (action.resumeAfterPolicyHold != NeuraApprovalStatus.approved) {
        throw StateError('Action $actionId is waiting to undo, not execute.');
      }
      action
        ..status = NeuraApprovalStatus.approved
        ..policyReason = null
        ..resumeAfterPolicyHold = null;
    }
    if (automatic && !_canAutoExecute(action)) return action.snapshot();
    if (action.status == NeuraApprovalStatus.pendingApproval) {
      throw StateError('Action $actionId requires explicit approval.');
    }
    if (action.status != NeuraApprovalStatus.approved) {
      throw StateError(
        'Action $actionId cannot execute from ${action.status.name}.',
      );
    }

    final current = registry.resolve(action.candidate.capabilityId);
    final configurationError = _configurationError(action, current);
    if (configurationError != null) {
      action
        ..status = NeuraApprovalStatus.blocked
        ..policyReason = configurationError;
      return action.snapshot();
    }
    if (_needsFreshApproval(current) && !action.explicitUserApproval) {
      action.status = NeuraApprovalStatus.pendingApproval;
      if (automatic) return action.snapshot();
      throw StateError('Action $actionId requires a fresh user approval.');
    }

    final verdict = await _runRevalidator(
      action,
      current,
      phase: NeuraApprovalPhase.execute,
      automatic: automatic,
    );
    if (!verdict.allowed) {
      action
        ..resumeAfterPolicyHold = NeuraApprovalStatus.approved
        ..status = NeuraApprovalStatus.policyHeld
        ..policyReason = _verdictReason(verdict);
      return action.snapshot();
    }
    _expireIfNeeded(action, _now());
    if (action.status == NeuraApprovalStatus.expired) {
      return action.snapshot();
    }

    final executor = _executors[current.id];
    if (executor == null) {
      action
        ..status = NeuraApprovalStatus.failed
        ..failure = 'No executor is registered for ${current.id}.';
      return action.snapshot();
    }

    action
      ..status = NeuraApprovalStatus.executing
      ..policyReason = null
      ..failure = null;
    final invocation = NeuraCapabilityInvocation(
      actionId: action.id,
      candidate: action.candidate,
      receipt: action.receipt,
      capability: current,
      invokedAt: now,
      automatic: automatic,
    );
    try {
      final result = await executor.execute(invocation);
      action
        ..status = NeuraApprovalStatus.executed
        ..executedAt = _now()
        ..executionResult = result;
    } catch (error) {
      action
        ..status = NeuraApprovalStatus.failed
        ..failure = 'Execution failed (${error.runtimeType}).';
    }
    return action.snapshot();
  }

  Future<NeuraApprovalAction> _undoAndClear(String actionId) async {
    try {
      return await _undoInternal(actionId);
    } finally {
      final _ = _undos.remove(actionId);
    }
  }

  Future<NeuraApprovalAction> _undoInternal(String actionId) async {
    final action = _requireAction(actionId);
    if (action.status == NeuraApprovalStatus.undone) return action.snapshot();
    if (action.status == NeuraApprovalStatus.policyHeld) {
      if (action.resumeAfterPolicyHold != NeuraApprovalStatus.executed) {
        throw StateError('Action $actionId is waiting to execute, not undo.');
      }
      action
        ..status = NeuraApprovalStatus.executed
        ..policyReason = null
        ..resumeAfterPolicyHold = null;
    }
    if (action.status != NeuraApprovalStatus.executed) {
      throw StateError(
        'Action $actionId cannot be undone from ${action.status.name}.',
      );
    }
    if (!action.capability.reversible) {
      throw StateError('Action $actionId is not reversible.');
    }

    final result = action.executionResult;
    if (result == null) {
      action
        ..status = NeuraApprovalStatus.failed
        ..failure = 'The execution result needed for undo is missing.';
      return action.snapshot();
    }

    final verdict = await _runRevalidator(
      action,
      action.capability,
      phase: NeuraApprovalPhase.undo,
      automatic: false,
    );
    if (!verdict.allowed) {
      action
        ..resumeAfterPolicyHold = NeuraApprovalStatus.executed
        ..status = NeuraApprovalStatus.policyHeld
        ..policyReason = _verdictReason(verdict);
      return action.snapshot();
    }

    final executor = _executors[action.capability.id];
    if (executor == null) {
      action
        ..status = NeuraApprovalStatus.failed
        ..failure = 'No executor is registered for ${action.capability.id}.';
      return action.snapshot();
    }

    action
      ..status = NeuraApprovalStatus.undoing
      ..policyReason = null
      ..failure = null;
    final invocation = NeuraCapabilityInvocation(
      actionId: action.id,
      candidate: action.candidate,
      receipt: action.receipt,
      capability: action.capability,
      invokedAt: _now(),
      automatic: false,
    );
    try {
      await executor.undo(invocation, result);
      action
        ..status = NeuraApprovalStatus.undone
        ..undoneAt = _now();
    } on NeuraUndoUnavailableException catch (error) {
      action
        ..status = NeuraApprovalStatus.executed
        ..failure = error.message;
    } catch (error) {
      action
        ..status = NeuraApprovalStatus.failed
        ..failure = 'Undo failed (${error.runtimeType}).';
    }
    return action.snapshot();
  }

  Future<NeuraPolicyVerdict> _runRevalidator(
    _MutableApprovalAction action,
    NeuraCapabilityDefinition capability, {
    required NeuraApprovalPhase phase,
    required bool automatic,
  }) async {
    late final bool safeMode;
    try {
      safeMode = _safeModeReader();
    } catch (error) {
      return NeuraPolicyVerdict.deny(
        'Safe Mode revalidation failed (${error.runtimeType}).',
      );
    }
    if (phase == NeuraApprovalPhase.execute &&
        safeMode &&
        capability.risk != NeuraCapabilityRisk.readOnly) {
      return const NeuraPolicyVerdict.deny(
        'Safe Mode holds actions that could change state.',
      );
    }

    final revalidator = _revalidator;
    if (revalidator == null) return const NeuraPolicyVerdict.allow();
    try {
      return await revalidator(
        NeuraApprovalPolicyContext(
          phase: phase,
          action: action.snapshot(),
          capability: capability,
          now: _now(),
          safeMode: safeMode,
          automatic: automatic,
        ),
      );
    } catch (error) {
      return NeuraPolicyVerdict.deny(
        'Policy revalidation failed (${error.runtimeType}).',
      );
    }
  }

  String? _submissionError(_MutableApprovalAction action) {
    final candidate = action.candidate;
    final receipt = action.receipt;
    final capability = action.capability;
    if (candidate.capabilityId.trim().isEmpty) {
      return 'The candidate has no capability id.';
    }
    if (candidate.id != receipt.candidateId ||
        candidate.capabilityId != receipt.capabilityId) {
      return 'The decision receipt does not match the submitted candidate.';
    }
    if (capability.id != candidate.capabilityId) {
      return 'The capability is not registered.';
    }
    if (receipt.risk != capability.risk) {
      return 'The capability risk changed after the decision was evaluated.';
    }
    if (receipt.outcome != NeuraDecisionOutcome.allow &&
        receipt.outcome != NeuraDecisionOutcome.askApproval) {
      return 'Suppressed or blocked decisions cannot be submitted for '
          'execution.';
    }
    if (!candidate.expiresAt.isAfter(candidate.createdAt)) {
      return 'The candidate has an invalid expiry window.';
    }
    if (capability.approvalMode == NeuraApprovalMode.blocked ||
        capability.risk == NeuraCapabilityRisk.critical) {
      return 'This capability is blocked by the autonomy policy.';
    }
    return null;
  }

  String? _configurationError(
    _MutableApprovalAction action,
    NeuraCapabilityDefinition current,
  ) {
    if (current.id != action.capability.id) {
      return 'The capability is no longer registered.';
    }
    if (!_sameCapability(current, action.capability) ||
        action.receipt.risk != current.risk) {
      return 'The capability policy changed; submit a new decision.';
    }
    if (current.approvalMode == NeuraApprovalMode.blocked ||
        current.risk == NeuraCapabilityRisk.critical) {
      return 'This capability is blocked by the current policy.';
    }
    return null;
  }

  bool _canAutoExecute(_MutableApprovalAction action) {
    final capability = action.capability;
    return action.status == NeuraApprovalStatus.approved &&
        action.receipt.outcome == NeuraDecisionOutcome.allow &&
        !action.receipt.requiresApproval &&
        capability.risk == NeuraCapabilityRisk.readOnly &&
        capability.approvalMode == NeuraApprovalMode.none &&
        !capability.hasExternalSideEffect;
  }

  bool _needsFreshApproval(NeuraCapabilityDefinition capability) =>
      _isElevated(capability) ||
      capability.approvalMode == NeuraApprovalMode.everyTime;

  bool _isElevated(NeuraCapabilityDefinition capability) =>
      capability.risk == NeuraCapabilityRisk.sensitiveLocal ||
      capability.risk == NeuraCapabilityRisk.external ||
      capability.risk == NeuraCapabilityRisk.critical ||
      capability.hasExternalSideEffect;

  bool _sameCapability(
    NeuraCapabilityDefinition left,
    NeuraCapabilityDefinition right,
  ) =>
      left.id == right.id &&
      left.risk == right.risk &&
      left.approvalMode == right.approvalMode &&
      left.reversible == right.reversible &&
      left.hasExternalSideEffect == right.hasExternalSideEffect;

  void _expireIfNeeded(_MutableApprovalAction action, DateTime now) {
    final canExpire = action.status == NeuraApprovalStatus.pendingApproval ||
        action.status == NeuraApprovalStatus.approved ||
        (action.status == NeuraApprovalStatus.policyHeld &&
            action.resumeAfterPolicyHold == NeuraApprovalStatus.approved);
    if (canExpire && !now.isBefore(action.candidate.expiresAt)) {
      action
        ..status = NeuraApprovalStatus.expired
        ..policyReason = null
        ..resumeAfterPolicyHold = null;
    }
  }

  void _assertSameDecision(
    NeuraCouncilDecision first,
    NeuraCouncilDecision second,
  ) {
    final left = first.candidate;
    final right = second.candidate;
    final leftReceipt = first.receipt;
    final rightReceipt = second.receipt;
    final sameCandidate = left.id == right.id &&
        left.capabilityId == right.capabilityId &&
        left.specialistId == right.specialistId &&
        left.title == right.title &&
        left.body == right.body &&
        left.createdAt.isAtSameMomentAs(right.createdAt) &&
        left.expiresAt.isAtSameMomentAs(right.expiresAt) &&
        left.benefit == right.benefit &&
        left.urgency == right.urgency &&
        left.disruption == right.disruption &&
        left.confidence == right.confidence &&
        _evidenceEquals(left.evidence, right.evidence) &&
        _deepEquals(left.payload, right.payload);
    final sameReceipt = leftReceipt.id == rightReceipt.id &&
        leftReceipt.candidateId == rightReceipt.candidateId &&
        leftReceipt.capabilityId == rightReceipt.capabilityId &&
        leftReceipt.specialistId == rightReceipt.specialistId &&
        leftReceipt.outcome == rightReceipt.outcome &&
        leftReceipt.risk == rightReceipt.risk &&
        leftReceipt.score == rightReceipt.score &&
        leftReceipt.requiresApproval == rightReceipt.requiresApproval &&
        _deepEquals(leftReceipt.reasons, rightReceipt.reasons) &&
        _deepEquals(leftReceipt.evidenceIds, rightReceipt.evidenceIds) &&
        leftReceipt.evaluatedAt.isAtSameMomentAs(rightReceipt.evaluatedAt) &&
        leftReceipt.userOutcome == rightReceipt.userOutcome;
    if (!sameCandidate || !sameReceipt) {
      throw StateError(
        'Candidate id ${second.candidate.id} was reused for a different '
        'action.',
      );
    }
  }

  bool _evidenceEquals(
    List<NeuraEvidenceRef> left,
    List<NeuraEvidenceRef> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.source != b.source ||
          a.summary != b.summary ||
          !a.observedAt.isAtSameMomentAs(b.observedAt) ||
          a.confidence != b.confidence ||
          a.sensitivity != b.sensitivity) {
        return false;
      }
    }
    return true;
  }

  bool _deepEquals(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final key in left.keys) {
        if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is Iterable && right is Iterable) {
      final a = left.toList(growable: false);
      final b = right.toList(growable: false);
      if (a.length != b.length) return false;
      for (var index = 0; index < a.length; index++) {
        if (!_deepEquals(a[index], b[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  _MutableApprovalAction _requireAction(String actionId) {
    final action = _actions[actionId];
    if (action == null) throw StateError('Unknown approval action: $actionId.');
    return action;
  }

  DateTime _now() => _clock().toUtc();

  /// Stops new authority checks, drains operations that may still hold raw
  /// proposal content, and forgets all process-local approvals and consent.
  Future<void> resetAfterDataWipe() async {
    _suspended = true;
    final pending = <Future<NeuraApprovalAction>>[
      ..._submissions.values,
      ..._executions.values,
      ..._undos.values,
    ];
    try {
      if (pending.isNotEmpty) {
        await Future.wait<void>(
          pending.map(
            (operation) => operation.then<void>(
              (_) {},
              onError: (_, __) {},
            ),
          ),
        ).timeout(const Duration(seconds: 3));
      }
    } finally {
      _actions.clear();
      _actionIdByCandidate.clear();
      _decisionByCandidate.clear();
      _submissions.clear();
      _executions.clear();
      _undos.clear();
      consentLedger.clear();
    }
  }

  /// Re-opens an empty broker only after the complete wipe transaction passes.
  void resumeAfterDataWipe() {
    _actions.clear();
    _actionIdByCandidate.clear();
    _decisionByCandidate.clear();
    _submissions.clear();
    _executions.clear();
    _undos.clear();
    consentLedger.clear();
    _suspended = false;
  }

  void _ensureActive() {
    if (_suspended) {
      throw StateError('Action approvals are suspended after a data wipe.');
    }
  }

  String _verdictReason(NeuraPolicyVerdict verdict) {
    final reason = verdict.reason?.trim();
    return reason == null || reason.isEmpty
        ? 'The current policy does not allow this action.'
        : reason;
  }

  static DateTime _systemClock() => DateTime.now().toUtc();

  static bool _safeModeOff() => false;

  static String _defaultIdFactory(
    NeuraIntelligenceCandidate candidate,
    DateTime now,
  ) =>
      '${candidate.id}:${now.microsecondsSinceEpoch}';
}

class _MutableApprovalAction {
  _MutableApprovalAction({
    required this.id,
    required this.candidate,
    required this.receipt,
    required this.capability,
    required this.status,
    required this.submittedAt,
  });

  final String id;
  final NeuraIntelligenceCandidate candidate;
  final NeuraDecisionReceipt receipt;
  final NeuraCapabilityDefinition capability;
  final DateTime submittedAt;
  NeuraApprovalStatus status;
  bool explicitUserApproval = false;
  DateTime? reviewedAt;
  DateTime? executedAt;
  DateTime? undoneAt;
  NeuraCapabilityExecutionResult? executionResult;
  String? denialReason;
  String? policyReason;
  String? failure;
  NeuraApprovalStatus? resumeAfterPolicyHold;

  NeuraApprovalAction snapshot() => NeuraApprovalAction(
        id: id,
        candidate: candidate,
        receipt: receipt,
        capability: capability,
        status: status,
        submittedAt: submittedAt,
        explicitUserApproval: explicitUserApproval,
        reviewedAt: reviewedAt,
        executedAt: executedAt,
        undoneAt: undoneAt,
        executionResult: executionResult,
        denialReason: denialReason,
        policyReason: policyReason,
        failure: failure,
      );
}
