import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/living_intelligence/living_intelligence.dart';

void main() {
  test('runtime approval status uses leases issued from the live clock', () {
    const context = NeuraSafetyContext(
      directUserGesture: true,
      freshApproval: true,
    );
    final runtime = NeuraLivingIntelligenceRuntime.create(
      safeModeReader: () => false,
    );
    runtime.setEnabled(true, context: context);
    final issuedAt = DateTime.now().toUtc();

    final issue = runtime.issueFreshApprovalLease(
      leaseId: 'live-clock-lease',
      actionFingerprint: 'sha256:live-clock-action',
      capabilityId: 'change_local_plan',
      contextCapsuleId: 'personal',
      deviceId: 'device-a',
      context: context,
      explicitApproval: true,
      capabilityRegistered: true,
      criticalCapability: false,
      involvesMoneyMovement: false,
      now: issuedAt,
    );

    expect(issue.issued, isTrue);
    expect(runtime.status(now: issuedAt).activeFreshApprovalLeases, 1);
  });
}
