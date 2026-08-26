import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/living_intelligence/living_intelligence.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 8, 26, 12);
  const policy = NeuraFreshApprovalLeasePolicy();
  const approvedContext = NeuraSafetyContext(
    directUserGesture: true,
    freshApproval: true,
  );

  NeuraFreshApprovalScope scope({
    String actionFingerprint = 'sha256:action-a',
    String capabilityId = 'change_local_plan',
    String capsuleId = 'personal',
    String deviceId = 'device-a',
  }) {
    return NeuraFreshApprovalScope(
      actionFingerprint: actionFingerprint,
      capabilityId: capabilityId,
      capsuleId: capsuleId,
      deviceId: deviceId,
    );
  }

  NeuraFreshApprovalIssue issue({
    String leaseId = 'lease-1',
    NeuraFreshApprovalScope? approvedScope,
    Duration lifetime = const Duration(seconds: 30),
    NeuraSafetyContext safetyContext = approvedContext,
    bool explicitApproval = true,
    bool capabilityRegistered = true,
    bool criticalCapability = false,
    bool involvesMoneyMovement = false,
    bool safeModeActive = false,
  }) {
    return policy.issue(
      leaseId: leaseId,
      scope: approvedScope ?? scope(),
      issuedAt: issuedAt,
      lifetime: lifetime,
      safetyContext: safetyContext,
      explicitApproval: explicitApproval,
      capabilityRegistered: capabilityRegistered,
      criticalCapability: criticalCapability,
      involvesMoneyMovement: involvesMoneyMovement,
      safeModeActive: safeModeActive,
    );
  }

  NeuraFreshApprovalReceipt authorize(
    NeuraFreshApprovalLease lease, {
    DateTime? now,
    NeuraFreshApprovalScope? requestedScope,
    NeuraSafetyContext safetyContext = approvedContext,
    bool actionLoomAuthority = true,
    bool capabilityRegistered = true,
    bool criticalCapability = false,
    bool involvesMoneyMovement = false,
    bool safeModeActive = false,
  }) {
    return lease.authorizeForActionLoom(
      now: now ?? issuedAt.add(const Duration(seconds: 1)),
      requestedScope: requestedScope ?? scope(),
      safetyContext: safetyContext,
      actionLoomAuthority: actionLoomAuthority,
      capabilityRegistered: capabilityRegistered,
      criticalCapability: criticalCapability,
      involvesMoneyMovement: involvesMoneyMovement,
      safeModeActive: safeModeActive,
    );
  }

  group('NeuraFreshApprovalLeasePolicy', () {
    test('Safe Mode and Recovery mode fail closed before issuance', () {
      final safeModeIssue = issue(safeModeActive: true);
      final recoveryIssue = issue(
        safetyContext: const NeuraSafetyContext(
          directUserGesture: true,
          freshApproval: true,
          recoveryMode: true,
        ),
      );

      expect(
        safeModeIssue.outcome,
        NeuraFreshApprovalOutcome.blockedBySafeMode,
      );
      expect(safeModeIssue.lease, isNull);
      expect(
        recoveryIssue.outcome,
        NeuraFreshApprovalOutcome.blockedByRecoveryMode,
      );
      expect(recoveryIssue.lease, isNull);
    });

    test('requires a direct gesture and explicit fresh approval', () {
      expect(
        issue(
          safetyContext: const NeuraSafetyContext(freshApproval: true),
        ).outcome,
        NeuraFreshApprovalOutcome.directUserGestureRequired,
      );
      expect(
        issue(
          safetyContext: const NeuraSafetyContext(
            directUserGesture: true,
          ),
        ).outcome,
        NeuraFreshApprovalOutcome.explicitApprovalRequired,
      );
      expect(
        issue(explicitApproval: false).outcome,
        NeuraFreshApprovalOutcome.explicitApprovalRequired,
      );
    });

    test('blocks unknown, critical, and money-moving capabilities', () {
      expect(
        issue(capabilityRegistered: false).outcome,
        NeuraFreshApprovalOutcome.capabilityNotRegistered,
      );
      expect(
        issue(criticalCapability: true).outcome,
        NeuraFreshApprovalOutcome.criticalCapabilityBlocked,
      );
      expect(
        issue(involvesMoneyMovement: true).outcome,
        NeuraFreshApprovalOutcome.moneyMovementBlocked,
      );
    });

    test('rejects wildcard scope and excessive lifetime', () {
      expect(
        () => scope(actionFingerprint: '*'),
        throwsArgumentError,
      );
      expect(
        issue(lifetime: const Duration(minutes: 3)).outcome,
        NeuraFreshApprovalOutcome.invalidRequest,
      );
      expect(
        issue(lifetime: Duration.zero).outcome,
        NeuraFreshApprovalOutcome.invalidRequest,
      );
    });
  });

  group('NeuraFreshApprovalLease authorization', () {
    test('authorizes the exact scope once and rejects replay', () {
      final lease = issue().lease!;

      final first = authorize(lease);
      final replay = authorize(lease);

      expect(first.authorized, isTrue);
      expect(first.grantsExecutionAuthority, isFalse);
      expect(lease.consumed, isTrue);
      expect(replay.authorized, isFalse);
      expect(
        replay.outcome,
        NeuraFreshApprovalOutcome.alreadyConsumed,
      );
    });

    test('scope mismatch does not consume a valid lease', () {
      final lease = issue().lease!;

      final mismatch = authorize(
        lease,
        requestedScope: scope(deviceId: 'device-b'),
      );
      final exact = authorize(lease);

      expect(mismatch.outcome, NeuraFreshApprovalOutcome.scopeMismatch);
      expect(exact.outcome, NeuraFreshApprovalOutcome.authorized);
    });

    test('revalidates all execution boundaries at use time', () {
      final noAuthority = issue(leaseId: 'no-authority').lease!;
      final safeMode = issue(leaseId: 'safe-mode').lease!;
      final recovery = issue(leaseId: 'recovery').lease!;
      final unregistered = issue(leaseId: 'unregistered').lease!;
      final critical = issue(leaseId: 'critical').lease!;
      final money = issue(leaseId: 'money').lease!;

      expect(
        authorize(noAuthority, actionLoomAuthority: false).outcome,
        NeuraFreshApprovalOutcome.actionLoomAuthorityRequired,
      );
      expect(
        authorize(safeMode, safeModeActive: true).outcome,
        NeuraFreshApprovalOutcome.blockedBySafeMode,
      );
      expect(
        authorize(
          recovery,
          safetyContext: const NeuraSafetyContext(
            directUserGesture: true,
            freshApproval: true,
            recoveryMode: true,
          ),
        ).outcome,
        NeuraFreshApprovalOutcome.blockedByRecoveryMode,
      );
      expect(
        authorize(unregistered, capabilityRegistered: false).outcome,
        NeuraFreshApprovalOutcome.capabilityNotRegistered,
      );
      expect(
        authorize(critical, criticalCapability: true).outcome,
        NeuraFreshApprovalOutcome.criticalCapabilityBlocked,
      );
      expect(
        authorize(money, involvesMoneyMovement: true).outcome,
        NeuraFreshApprovalOutcome.moneyMovementBlocked,
      );
      expect(noAuthority.consumed, isFalse);
      expect(safeMode.consumed, isFalse);
      expect(recovery.consumed, isFalse);
      expect(unregistered.consumed, isFalse);
      expect(critical.consumed, isFalse);
      expect(money.consumed, isFalse);
    });

    test('rejects clock rollback and expiry at the exact boundary', () {
      final earlyLease = issue(leaseId: 'early').lease!;
      final expiredLease = issue(leaseId: 'expired').lease!;

      expect(
        authorize(
          earlyLease,
          now: issuedAt.subtract(const Duration(microseconds: 1)),
        ).outcome,
        NeuraFreshApprovalOutcome.notYetValid,
      );
      expect(
        authorize(
          expiredLease,
          now: issuedAt.add(const Duration(seconds: 30)),
        ).outcome,
        NeuraFreshApprovalOutcome.expired,
      );
    });

    test('revocation is deterministic and privacy-bounded', () {
      final lease = issue(leaseId: 'revoked-lease').lease!;

      final revoked = lease.revoke(
        now: issuedAt.add(const Duration(seconds: 1)),
      );
      final denied = authorize(lease);

      expect(revoked.outcome, NeuraFreshApprovalOutcome.revoked);
      expect(revoked.leaseId, 'revoked-lease');
      expect(revoked.evaluatedAtUtc.isUtc, isTrue);
      expect(revoked.grantsExecutionAuthority, isFalse);
      expect(lease.revoked, isTrue);
      expect(denied.outcome, NeuraFreshApprovalOutcome.revoked);
    });
  });

  group('NeuraActionLoomFreshApprovalGate', () {
    const gate = NeuraActionLoomFreshApprovalGate();

    test('never invokes the mutation callback when authorization fails', () async {
      final lease = issue(leaseId: 'blocked-callback').lease!;
      var callbackCalls = 0;

      final result = await gate.commit<int>(
        lease: lease,
        requestedScope: scope(),
        safetyContext: approvedContext,
        actionLoomAuthority: false,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        safeModeActive: false,
        now: issuedAt.add(const Duration(seconds: 1)),
        actionLoomCommit: () async {
          callbackCalls += 1;
          return 1;
        },
      );

      expect(result.committed, isFalse);
      expect(result.value, isNull);
      expect(callbackCalls, 0);
      expect(lease.consumed, isFalse);
      expect(
        result.receipt.outcome,
        NeuraFreshApprovalOutcome.actionLoomAuthorityRequired,
      );
    });

    test('consumes before commit so a failed mutation cannot replay', () async {
      final lease = issue(leaseId: 'throwing-commit').lease!;
      var callbackCalls = 0;

      await expectLater(
        gate.commit<void>(
          lease: lease,
          requestedScope: scope(),
          safetyContext: approvedContext,
          actionLoomAuthority: true,
          capabilityRegistered: true,
          criticalCapability: false,
          involvesMoneyMovement: false,
          safeModeActive: false,
          now: issuedAt.add(const Duration(seconds: 1)),
          actionLoomCommit: () async {
            callbackCalls += 1;
            throw StateError('synthetic commit failure');
          },
        ),
        throwsStateError,
      );

      expect(callbackCalls, 1);
      expect(lease.consumed, isTrue);

      final replay = await gate.commit<int>(
        lease: lease,
        requestedScope: scope(),
        safetyContext: approvedContext,
        actionLoomAuthority: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        safeModeActive: false,
        now: issuedAt.add(const Duration(seconds: 2)),
        actionLoomCommit: () async {
          callbackCalls += 1;
          return 2;
        },
      );
      expect(replay.committed, isFalse);
      expect(
        replay.receipt.outcome,
        NeuraFreshApprovalOutcome.alreadyConsumed,
      );
      expect(callbackCalls, 1);
    });

    test('runs one exact Action Loom commit and returns its value', () async {
      final lease = issue(leaseId: 'successful-commit').lease!;
      var callbackCalls = 0;

      final result = await gate.commit<String>(
        lease: lease,
        requestedScope: scope(),
        safetyContext: approvedContext,
        actionLoomAuthority: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        safeModeActive: false,
        now: issuedAt.add(const Duration(seconds: 1)),
        actionLoomCommit: () async {
          callbackCalls += 1;
          return 'committed';
        },
      );

      expect(result.committed, isTrue);
      expect(result.value, 'committed');
      expect(result.grantsExecutionAuthority, isFalse);
      expect(callbackCalls, 1);
      expect(lease.consumed, isTrue);
    });
  });
}
