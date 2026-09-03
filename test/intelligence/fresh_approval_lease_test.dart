import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/fresh_approval_lease.dart';

void main() {
  const exactScope = NeuraFreshApprovalScope(
    actionId: 'action-1',
    candidateId: 'candidate-1',
    receiptId: 'receipt-1',
    capabilityId: 'change_local_plan',
  );
  final issuedAt = DateTime.utc(2026, 8, 26, 12);

  test('issues bounded non-authoritative approval evidence', () {
    final registry = NeuraFreshApprovalLeaseRegistry();
    final lease = registry.issue(
      scope: exactScope,
      issuedAt: issuedAt,
    );

    expect(lease.grantsExecutionAuthority, isFalse);
    expect(lease.issuedAtUtc, issuedAt);
    expect(lease.expiresAtUtc, issuedAt.add(const Duration(minutes: 2)));
    expect(
      registry.stateOf(
        exactScope.actionId,
        now: issuedAt.add(const Duration(seconds: 1)),
      ),
      NeuraFreshApprovalLeaseState.active,
    );
  });

  test('consumes the exact scope once and rejects replay', () {
    final registry = NeuraFreshApprovalLeaseRegistry();
    registry.issue(scope: exactScope, issuedAt: issuedAt);

    final first = registry.validateAndConsume(
      scope: exactScope,
      now: issuedAt.add(const Duration(seconds: 1)),
    );
    final replay = registry.validateAndConsume(
      scope: exactScope,
      now: issuedAt.add(const Duration(seconds: 2)),
    );

    expect(first.allowed, isTrue);
    expect(first.state, NeuraFreshApprovalLeaseState.consumed);
    expect(first.grantsExecutionAuthority, isFalse);
    expect(replay.allowed, isFalse);
    expect(replay.state, NeuraFreshApprovalLeaseState.consumed);
  });

  test('scope mismatch fails closed without consuming the valid lease', () {
    final registry = NeuraFreshApprovalLeaseRegistry();
    registry.issue(scope: exactScope, issuedAt: issuedAt);
    const mismatch = NeuraFreshApprovalScope(
      actionId: 'action-1',
      candidateId: 'candidate-1',
      receiptId: 'receipt-other',
      capabilityId: 'change_local_plan',
    );

    final denied = registry.validateAndConsume(
      scope: mismatch,
      now: issuedAt.add(const Duration(seconds: 1)),
    );
    final exact = registry.validateAndConsume(
      scope: exactScope,
      now: issuedAt.add(const Duration(seconds: 2)),
    );

    expect(denied.allowed, isFalse);
    expect(denied.state, NeuraFreshApprovalLeaseState.scopeMismatch);
    expect(exact.allowed, isTrue);
  });

  test('rejects clock rollback, short remaining time, and exact expiry', () {
    final registry = NeuraFreshApprovalLeaseRegistry();
    registry.issue(
      scope: exactScope,
      issuedAt: issuedAt,
      lifetime: const Duration(seconds: 30),
    );

    final early = registry.validate(
      scope: exactScope,
      now: issuedAt.subtract(const Duration(microseconds: 1)),
    );
    final tooClose = registry.validate(
      scope: exactScope,
      now: issuedAt.add(const Duration(seconds: 26)),
      minimumRemaining: const Duration(seconds: 5),
    );
    final expired = registry.validate(
      scope: exactScope,
      now: issuedAt.add(const Duration(seconds: 30)),
    );

    expect(early.state, NeuraFreshApprovalLeaseState.notYetValid);
    expect(
      tooClose.state,
      NeuraFreshApprovalLeaseState.insufficientLifetime,
    );
    expect(expired.state, NeuraFreshApprovalLeaseState.expired);
  });

  test('hard action expiry shortens the lease', () {
    final registry = NeuraFreshApprovalLeaseRegistry();
    final hardDeadline = issuedAt.add(const Duration(seconds: 45));
    final lease = registry.issue(
      scope: exactScope,
      issuedAt: issuedAt,
      notAfter: hardDeadline,
    );

    expect(lease.expiresAtUtc, hardDeadline);
  });

  test('revocation and data wipe are deterministic', () {
    final registry = NeuraFreshApprovalLeaseRegistry();
    registry.issue(scope: exactScope, issuedAt: issuedAt);

    expect(
      registry.revokeForAction(
        exactScope.actionId,
        now: issuedAt.add(const Duration(seconds: 1)),
      ),
      isTrue,
    );
    expect(
      registry.stateOf(
        exactScope.actionId,
        now: issuedAt.add(const Duration(seconds: 2)),
      ),
      NeuraFreshApprovalLeaseState.revoked,
    );

    registry.clear();
    expect(registry.recordCount, 0);
    expect(
      registry.stateOf(exactScope.actionId, now: issuedAt),
      NeuraFreshApprovalLeaseState.missing,
    );
  });

  test('invalid scope and excessive lifetime are rejected', () {
    final registry = NeuraFreshApprovalLeaseRegistry();
    expect(
      () => registry.issue(
        scope: const NeuraFreshApprovalScope(
          actionId: '*',
          candidateId: 'candidate-1',
          receiptId: 'receipt-1',
          capabilityId: 'change_local_plan',
        ),
        issuedAt: issuedAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => registry.issue(
        scope: exactScope,
        issuedAt: issuedAt,
        lifetime: const Duration(minutes: 3),
      ),
      throwsArgumentError,
    );
  });
}
