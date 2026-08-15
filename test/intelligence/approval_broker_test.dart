import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/approval_broker.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/consent_ledger.dart';
import 'package:neuro_companion/intelligence/models.dart';

class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

class _FakeExecutor implements NeuraCapabilityExecutor {
  int executeCalls = 0;
  int undoCalls = 0;
  bool throwOnExecute = false;
  Completer<void>? executeGate;
  NeuraCapabilityInvocation? lastInvocation;

  @override
  Future<NeuraCapabilityExecutionResult> execute(
    NeuraCapabilityInvocation invocation,
  ) async {
    executeCalls += 1;
    lastInvocation = invocation;
    if (throwOnExecute) throw StateError('uncertain failure');
    final gate = executeGate;
    if (gate != null) await gate.future;
    return NeuraCapabilityExecutionResult(
      value: 'done-${invocation.actionId}',
      undoToken: 'undo-${invocation.actionId}',
    );
  }

  @override
  Future<void> undo(
    NeuraCapabilityInvocation invocation,
    NeuraCapabilityExecutionResult result,
  ) async {
    undoCalls += 1;
  }
}

NeuraCouncilDecision _decision({
  required String candidateId,
  required String capabilityId,
  required NeuraCapabilityRisk risk,
  required DateTime now,
  NeuraDecisionOutcome outcome = NeuraDecisionOutcome.allow,
  bool requiresApproval = false,
  Duration lifetime = const Duration(minutes: 15),
  Map<String, Object?> payload = const {},
}) {
  final candidate = NeuraIntelligenceCandidate(
    id: candidateId,
    capabilityId: capabilityId,
    specialistId: 'test-specialist',
    title: 'Test action',
    body: 'A deterministic test action.',
    createdAt: now,
    expiresAt: now.add(lifetime),
    payload: payload,
  );
  final receipt = NeuraDecisionReceipt(
    id: 'receipt-$candidateId',
    candidateId: candidateId,
    capabilityId: capabilityId,
    specialistId: 'test-specialist',
    outcome: outcome,
    risk: risk,
    score: 0.9,
    requiresApproval: requiresApproval,
    reasons: const ['test'],
    evidenceIds: const [],
    evaluatedAt: now,
  );
  return NeuraCouncilDecision(candidate: candidate, receipt: receipt);
}

NeuraApprovalBroker _broker({
  required _Clock clock,
  required Map<String, NeuraCapabilityExecutor> executors,
  NeuraCapabilityRegistry? registry,
  NeuraConsentLedger? consentLedger,
  bool Function()? safeModeReader,
  NeuraApprovalRevalidator? revalidator,
}) {
  return NeuraApprovalBroker(
    executors: executors,
    registry: registry,
    consentLedger: consentLedger,
    clock: clock.call,
    idFactory: (candidate, _) => 'action-${candidate.id}',
    safeModeReader: safeModeReader,
    revalidator: revalidator,
  );
}

void main() {
  group('submission binding', () {
    test('concurrent candidate-id reuse with a different payload fails closed',
        () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final gate = Completer<NeuraPolicyVerdict>();
      final broker = _broker(
        clock: clock,
        executors: {
          NeuraCapabilityRegistry.changeLocalPlan: _FakeExecutor(),
        },
        revalidator: (_) => gate.future,
      );
      final first = _decision(
        candidateId: 'bound-1',
        capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
        risk: NeuraCapabilityRisk.reversibleLocal,
        now: clock.now,
        requiresApproval: true,
        outcome: NeuraDecisionOutcome.askApproval,
        payload: const {'action': 'draft_quest', 'goal': 'First'},
      );
      final changed = _decision(
        candidateId: 'bound-1',
        capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
        risk: NeuraCapabilityRisk.reversibleLocal,
        now: clock.now,
        requiresApproval: true,
        outcome: NeuraDecisionOutcome.askApproval,
        payload: const {'action': 'draft_quest', 'goal': 'Changed'},
      );

      final inFlight = broker.submit(first);
      expect(() => broker.submit(changed), throwsStateError);
      gate.complete(const NeuraPolicyVerdict.allow());
      expect(
        (await inFlight).status,
        NeuraApprovalStatus.pendingApproval,
      );
    });

    test('candidate payload and evidence collections are deeply frozen', () {
      final now = DateTime.utc(2026, 8, 14, 12);
      final nested = <Object?>['first'];
      final payload = <String, Object?>{'nested': nested};
      final evidence = <NeuraEvidenceRef>[
        NeuraEvidenceRef(
          id: 'e-1',
          source: 'test',
          summary: 'Test evidence',
          observedAt: now,
          confidence: 1,
          sensitivity: NeuraSensitivity.routine,
        ),
      ];
      final candidate = NeuraIntelligenceCandidate(
        id: 'frozen-1',
        capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
        specialistId: 'test',
        title: 'Frozen',
        body: 'Immutable review payload',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        payload: payload,
        evidence: evidence,
      );

      nested.add('mutated');
      payload['new'] = true;
      evidence.clear();

      expect(candidate.payload.containsKey('new'), isFalse);
      expect(candidate.payload['nested'], ['first']);
      expect(candidate.evidence, hasLength(1));
      expect(
        () => (candidate.payload['nested']! as List<Object?>).add('blocked'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('auto-execution boundary', () {
    test('read-only auto-execution is idempotent', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      final broker = _broker(
        clock: clock,
        executors: {
          NeuraCapabilityRegistry.surfaceSuggestion: executor,
        },
      );
      final decision = _decision(
        candidateId: 'read-1',
        capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
        risk: NeuraCapabilityRisk.readOnly,
        now: clock.now,
      );

      final first = await broker.submit(decision, autoExecute: true);
      final duplicate = await broker.submit(decision, autoExecute: true);
      final executedAgain = await broker.execute(first.id);

      expect(first.status, NeuraApprovalStatus.executed);
      expect(duplicate.id, first.id);
      expect(executedAgain.status, NeuraApprovalStatus.executed);
      expect(executor.executeCalls, 1);
      expect(executor.lastInvocation!.automatic, isTrue);
    });

    test('concurrent execution calls share one executor invocation', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor()..executeGate = Completer<void>();
      final broker = _broker(
        clock: clock,
        executors: {
          NeuraCapabilityRegistry.surfaceSuggestion: executor,
        },
      );
      final decision = _decision(
        candidateId: 'concurrent-1',
        capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
        risk: NeuraCapabilityRisk.readOnly,
        now: clock.now,
      );
      final submitted = await broker.submit(decision);

      final first = broker.execute(submitted.id);
      final second = broker.execute(submitted.id);
      executor.executeGate!.complete();
      final results = await Future.wait([first, second]);

      expect(results.map((result) => result.status), [
        NeuraApprovalStatus.executed,
        NeuraApprovalStatus.executed,
      ]);
      expect(executor.executeCalls, 1);
    });

    test('never auto-runs external actions', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      final broker = _broker(
        clock: clock,
        executors: {
          NeuraCapabilityRegistry.scheduleNotification: executor,
        },
      );
      final decision = _decision(
        candidateId: 'external-1',
        capabilityId: NeuraCapabilityRegistry.scheduleNotification,
        risk: NeuraCapabilityRisk.external,
        now: clock.now,
        outcome: NeuraDecisionOutcome.askApproval,
        requiresApproval: true,
      );

      final submitted = await broker.submit(decision, autoExecute: true);

      expect(submitted.status, NeuraApprovalStatus.pendingApproval);
      expect(executor.executeCalls, 0);
      await expectLater(
        broker.execute(submitted.id),
        throwsA(isA<StateError>()),
      );

      final approved = broker.approve(submitted.id);
      final executed = await broker.execute(approved.id);
      final executedAgain = await broker.execute(approved.id);

      expect(approved.explicitUserApproval, isTrue);
      expect(executed.status, NeuraApprovalStatus.executed);
      expect(executedAgain.status, NeuraApprovalStatus.executed);
      expect(executor.executeCalls, 1);
    });

    test('never auto-runs sensitive actions', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      final broker = _broker(
        clock: clock,
        executors: {
          NeuraCapabilityRegistry.exportPrivateData: executor,
        },
      );
      final decision = _decision(
        candidateId: 'sensitive-1',
        capabilityId: NeuraCapabilityRegistry.exportPrivateData,
        risk: NeuraCapabilityRisk.sensitiveLocal,
        now: clock.now,
        outcome: NeuraDecisionOutcome.askApproval,
        requiresApproval: true,
      );

      final submitted = await broker.submit(decision, autoExecute: true);

      expect(submitted.status, NeuraApprovalStatus.pendingApproval);
      expect(executor.executeCalls, 0);
    });

    test('critical actions cannot be approved', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      final broker = _broker(
        clock: clock,
        executors: {NeuraCapabilityRegistry.moveMoney: executor},
      );
      final decision = _decision(
        candidateId: 'critical-1',
        capabilityId: NeuraCapabilityRegistry.moveMoney,
        risk: NeuraCapabilityRisk.critical,
        now: clock.now,
        outcome: NeuraDecisionOutcome.askApproval,
        requiresApproval: true,
      );

      final submitted = await broker.submit(decision, autoExecute: true);
      final approved = broker.approve(submitted.id);

      expect(submitted.status, NeuraApprovalStatus.blocked);
      expect(approved.status, NeuraApprovalStatus.blocked);
      expect(executor.executeCalls, 0);
    });
  });

  group('lifecycle and revalidation', () {
    test('deny is idempotent and prevents execution', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      final broker = _broker(
        clock: clock,
        executors: {NeuraCapabilityRegistry.changeLocalPlan: executor},
      );
      final decision = _decision(
        candidateId: 'deny-1',
        capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
        risk: NeuraCapabilityRisk.reversibleLocal,
        now: clock.now,
        outcome: NeuraDecisionOutcome.askApproval,
        requiresApproval: true,
      );
      final submitted = await broker.submit(decision);

      final denied = broker.deny(submitted.id, reason: 'Not today.');
      final deniedAgain = broker.deny(submitted.id);

      expect(denied.status, NeuraApprovalStatus.denied);
      expect(denied.denialReason, 'Not today.');
      expect(deniedAgain.status, NeuraApprovalStatus.denied);
      await expectLater(
        broker.execute(submitted.id),
        throwsA(isA<StateError>()),
      );
      expect(executor.executeCalls, 0);
    });

    test('approval expires before execution', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      final broker = _broker(
        clock: clock,
        executors: {NeuraCapabilityRegistry.changeLocalPlan: executor},
      );
      final decision = _decision(
        candidateId: 'expiry-1',
        capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
        risk: NeuraCapabilityRisk.reversibleLocal,
        now: clock.now,
        outcome: NeuraDecisionOutcome.askApproval,
        requiresApproval: true,
        lifetime: const Duration(minutes: 1),
      );
      final submitted = await broker.submit(decision);
      clock.advance(const Duration(minutes: 2));

      final expired = broker.approve(submitted.id);

      expect(expired.status, NeuraApprovalStatus.expired);
      await expectLater(
        broker.execute(submitted.id),
        throwsA(isA<StateError>()),
      );
      expect(executor.executeCalls, 0);
    });

    test('Safe Mode holds execution until disabled', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      var safeMode = true;
      final broker = _broker(
        clock: clock,
        executors: {NeuraCapabilityRegistry.openAppModule: executor},
        safeModeReader: () => safeMode,
      );
      final decision = _decision(
        candidateId: 'safe-mode-1',
        capabilityId: NeuraCapabilityRegistry.openAppModule,
        risk: NeuraCapabilityRisk.reversibleLocal,
        now: clock.now,
      );
      final submitted = await broker.submit(decision);

      final held = await broker.execute(submitted.id);
      safeMode = false;
      final executed = await broker.execute(submitted.id);

      expect(held.status, NeuraApprovalStatus.policyHeld);
      expect(held.policyReason, contains('Safe Mode'));
      expect(executed.status, NeuraApprovalStatus.executed);
      expect(executor.executeCalls, 1);
    });

    test('policy is revalidated immediately before execution', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      var executionAllowed = false;
      final broker = _broker(
        clock: clock,
        executors: {
          NeuraCapabilityRegistry.surfaceSuggestion: executor,
        },
        revalidator: (context) {
          if (context.phase == NeuraApprovalPhase.execute &&
              !executionAllowed) {
            return const NeuraPolicyVerdict.deny('Policy changed.');
          }
          return const NeuraPolicyVerdict.allow();
        },
      );
      final decision = _decision(
        candidateId: 'policy-1',
        capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
        risk: NeuraCapabilityRisk.readOnly,
        now: clock.now,
      );
      final submitted = await broker.submit(decision);

      final held = await broker.execute(submitted.id);
      executionAllowed = true;
      final executed = await broker.execute(submitted.id);

      expect(held.status, NeuraApprovalStatus.policyHeld);
      expect(held.policyReason, 'Policy changed.');
      expect(executed.status, NeuraApprovalStatus.executed);
      expect(executor.executeCalls, 1);
    });

    test('undo is idempotent and remains available in Safe Mode', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      var safeMode = false;
      final broker = _broker(
        clock: clock,
        executors: {NeuraCapabilityRegistry.openAppModule: executor},
        safeModeReader: () => safeMode,
      );
      final decision = _decision(
        candidateId: 'undo-1',
        capabilityId: NeuraCapabilityRegistry.openAppModule,
        risk: NeuraCapabilityRisk.reversibleLocal,
        now: clock.now,
      );
      final submitted = await broker.submit(decision);
      final executed = await broker.execute(submitted.id);
      safeMode = true;

      final undone = await broker.undo(executed.id);
      final undoneAgain = await broker.undo(executed.id);

      expect(undone.status, NeuraApprovalStatus.undone);
      expect(undoneAgain.status, NeuraApprovalStatus.undone);
      expect(executor.undoCalls, 1);
    });

    test('failed execution is not retried implicitly', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor()..throwOnExecute = true;
      final broker = _broker(
        clock: clock,
        executors: {
          NeuraCapabilityRegistry.surfaceSuggestion: executor,
        },
      );
      final decision = _decision(
        candidateId: 'failure-1',
        capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
        risk: NeuraCapabilityRisk.readOnly,
        now: clock.now,
      );
      final submitted = await broker.submit(decision);

      final failed = await broker.execute(submitted.id);
      final failedAgain = await broker.execute(submitted.id);

      expect(failed.status, NeuraApprovalStatus.failed);
      expect(failed.failure, contains('StateError'));
      expect(failedAgain.status, NeuraApprovalStatus.failed);
      expect(executor.executeCalls, 1);
    });
  });

  group('consent and receipt integrity', () {
    test('session consent covers later low-risk actions', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      const capability = NeuraCapabilityDefinition(
        id: 'session-local',
        title: 'Session local action',
        description: 'A low-risk action allowed for this session.',
        risk: NeuraCapabilityRisk.reversibleLocal,
        approvalMode: NeuraApprovalMode.session,
        reversible: true,
        hasExternalSideEffect: false,
      );
      final registry = NeuraCapabilityRegistry(capabilities: [capability]);
      final ledger = NeuraConsentLedger();
      final broker = _broker(
        clock: clock,
        executors: {capability.id: executor},
        registry: registry,
        consentLedger: ledger,
      );
      final firstDecision = _decision(
        candidateId: 'session-1',
        capabilityId: capability.id,
        risk: capability.risk,
        now: clock.now,
        outcome: NeuraDecisionOutcome.askApproval,
        requiresApproval: true,
      );
      final first = await broker.submit(firstDecision);
      broker.approve(first.id);

      final secondDecision = _decision(
        candidateId: 'session-2',
        capabilityId: capability.id,
        risk: capability.risk,
        now: clock.now,
      );
      final second = await broker.submit(
        secondDecision,
        autoExecute: true,
      );

      expect(second.status, NeuraApprovalStatus.approved);
      expect(second.explicitUserApproval, isFalse);
      expect(executor.executeCalls, 0);
    });

    test('mismatched decision receipts fail closed', () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      final broker = _broker(
        clock: clock,
        executors: {
          NeuraCapabilityRegistry.surfaceSuggestion: executor,
        },
      );
      final valid = _decision(
        candidateId: 'integrity-1',
        capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
        risk: NeuraCapabilityRisk.readOnly,
        now: clock.now,
      );
      final mismatchedReceipt = NeuraDecisionReceipt(
        id: 'receipt-mismatch',
        candidateId: 'another-candidate',
        capabilityId: valid.receipt.capabilityId,
        specialistId: valid.receipt.specialistId,
        outcome: valid.receipt.outcome,
        risk: valid.receipt.risk,
        score: valid.receipt.score,
        requiresApproval: valid.receipt.requiresApproval,
        reasons: valid.receipt.reasons,
        evidenceIds: valid.receipt.evidenceIds,
        evaluatedAt: valid.receipt.evaluatedAt,
      );
      final decision = NeuraCouncilDecision(
        candidate: valid.candidate,
        receipt: mismatchedReceipt,
      );

      final submitted = await broker.submit(decision, autoExecute: true);

      expect(submitted.status, NeuraApprovalStatus.blocked);
      expect(submitted.policyReason, contains('does not match'));
      expect(executor.executeCalls, 0);
    });
  });

  group('data-wipe lifecycle', () {
    test('suspends authority and forgets actions and session consent',
        () async {
      final clock = _Clock(DateTime.utc(2026, 8, 14, 12));
      final executor = _FakeExecutor();
      const capability = NeuraCapabilityDefinition(
        id: 'wipe-session-local',
        title: 'Wipe test action',
        description: 'A session capability used to verify revocation.',
        risk: NeuraCapabilityRisk.reversibleLocal,
        approvalMode: NeuraApprovalMode.session,
        reversible: true,
        hasExternalSideEffect: false,
      );
      final registry = NeuraCapabilityRegistry(capabilities: [capability]);
      final ledger = NeuraConsentLedger();
      final broker = _broker(
        clock: clock,
        executors: {capability.id: executor},
        registry: registry,
        consentLedger: ledger,
      );
      final decision = _decision(
        candidateId: 'wipe-1',
        capabilityId: capability.id,
        risk: capability.risk,
        now: clock.now,
        outcome: NeuraDecisionOutcome.askApproval,
        requiresApproval: true,
        payload: const {'private': 'must leave memory'},
      );
      final submitted = await broker.submit(decision);
      broker.approve(submitted.id);
      expect(ledger.activeAt(clock.now), isNotEmpty);

      await broker.resetAfterDataWipe();

      expect(broker.actions, isEmpty);
      expect(broker.find(submitted.id), isNull);
      expect(ledger.activeAt(clock.now), isEmpty);
      expect(() => broker.submit(decision), throwsStateError);

      broker.resumeAfterDataWipe();
      final fresh = _decision(
        candidateId: 'wipe-2',
        capabilityId: capability.id,
        risk: capability.risk,
        now: clock.now,
        outcome: NeuraDecisionOutcome.askApproval,
        requiresApproval: true,
      );
      expect(
        (await broker.submit(fresh)).status,
        NeuraApprovalStatus.pendingApproval,
      );
    });
  });
}
