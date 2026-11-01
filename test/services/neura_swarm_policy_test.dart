import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_swarm_policy.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 10, 30, 12);

  test('approval is short-lived and single-use', () {
    final approval = NeuraSwarmApproval.grantFromVisibleConfirmation(
      now: issuedAt,
      lifetime: const Duration(minutes: 5),
    );

    expect(
      approval.consume(
        now: issuedAt.add(const Duration(minutes: 4, seconds: 59)),
        foreground: true,
        safeMode: false,
      ),
      isTrue,
    );
    expect(approval.isConsumed, isTrue);
    expect(
      approval.consume(
        now: issuedAt.add(const Duration(minutes: 4, seconds: 59)),
        foreground: true,
        safeMode: false,
      ),
      isFalse,
    );
  });

  test('expiry and clock rollback fail closed', () {
    final approval = NeuraSwarmApproval.grantFromVisibleConfirmation(
      now: issuedAt,
    );

    expect(
      approval.consume(
        now: issuedAt.subtract(const Duration(seconds: 1)),
        foreground: true,
        safeMode: false,
      ),
      isFalse,
    );
    expect(
      approval.consume(
        now: issuedAt.add(const Duration(minutes: 5)),
        foreground: true,
        safeMode: false,
      ),
      isFalse,
    );
    expect(approval.isConsumed, isFalse);
  });

  test('background and Safe Mode cannot consume approval', () {
    final approval = NeuraSwarmApproval.grantFromVisibleConfirmation(
      now: issuedAt,
    );

    expect(
      approval.consume(
        now: issuedAt.add(const Duration(seconds: 1)),
        foreground: false,
        safeMode: false,
      ),
      isFalse,
    );
    expect(
      approval.consume(
        now: issuedAt.add(const Duration(seconds: 2)),
        foreground: true,
        safeMode: true,
      ),
      isFalse,
    );
    expect(approval.isConsumed, isFalse);
  });

  test('visible confirmation cannot mint an unbounded approval', () {
    expect(
      () => NeuraSwarmApproval.grantFromVisibleConfirmation(
        now: issuedAt,
        lifetime: const Duration(minutes: 6),
      ),
      throwsArgumentError,
    );
  });
}
