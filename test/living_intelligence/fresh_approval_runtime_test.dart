import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/living_intelligence/living_intelligence.dart';
import 'package:neuro_companion/living_intelligence/safety/fresh_approval_registry.dart';

void main() {
  const approvedContext = NeuraSafetyContext(
    directUserGesture: true,
    freshApproval: true,
  );
  final now = DateTime.utc(2026, 8, 26, 12);

  NeuraFreshApprovalScope scope(String fingerprint) {
    return NeuraFreshApprovalScope(
      actionFingerprint: fingerprint,
      capabilityId: 'change_local_plan',
      capsuleId: 'personal',
      deviceId: 'device-a',
    );
  }

  group('NeuraFreshApprovalLeaseRegistry', () {
    test('bounds active leases and rejects duplicate identifiers', () {
      final registry = NeuraFreshApprovalLeaseRegistry(maximumActiveLeases: 2);

      NeuraFreshApprovalIssue issue(String id, String fingerprint) {
        return registry.issue(
          leaseId: id,
          scope: scope(fingerprint),
          issuedAt: now,
          lifetime: const Duration(minutes: 1),
          safetyContext: approvedContext,
          explicitApproval: true,
          capabilityRegistered: true,
          criticalCapability: false,
          involvesMoneyMovement: false,
          safeModeActive: false,
        );
      }

      expect(issue('lease-1', 'sha256:a').issued, isTrue);
      expect(issue('lease-2', 'sha256:b').issued, isTrue);
      expect(
        issue('lease-1', 'sha256:c').outcome,
        NeuraFreshApprovalOutcome.invalidRequest,
      );
      expect(
        issue('lease-3', 'sha256:c').outcome,
        NeuraFreshApprovalOutcome.invalidRequest,
      );
      expect(registry.activeLeaseCount(now: now), 2);
    });

    test('removes expired or consumed leases before new issuance', () {
      final registry = NeuraFreshApprovalLeaseRegistry(maximumActiveLeases: 1);
      final first = registry.issue(
        leaseId: 'lease-1',
        scope: scope('sha256:a'),
        issuedAt: now,
        lifetime: const Duration(seconds: 5),
        safetyContext: approvedContext,
        explicitApproval: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        safeModeActive: false,
      );
      expect(first.issued, isTrue);

      final afterExpiry = registry.issue(
        leaseId: 'lease-2',
        scope: scope('sha256:b'),
        issuedAt: now.add(const Duration(seconds: 6)),
        lifetime: const Duration(seconds: 5),
        safetyContext: approvedContext,
        explicitApproval: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        safeModeActive: false,
      );
      expect(afterExpiry.issued, isTrue);
      expect(registry.find('lease-1'), isNull);
    });

    test('data wipe revokes and removes all retained leases', () {
      final registry = NeuraFreshApprovalLeaseRegistry();
      final issue = registry.issue(
        leaseId: 'lease-1',
        scope: scope('sha256:a'),
        issuedAt: now,
        lifetime: const Duration(minutes: 1),
        safetyContext: approvedContext,
        explicitApproval: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        safeModeActive: false,
      );
      final lease = issue.lease!;

      registry.resetAfterDataWipe(now: now.add(const Duration(seconds: 1)));

      expect(lease.revoked, isTrue);
      expect(registry.find('lease-1'), isNull);
      expect(registry.activeLeaseCount(now: now), 0);
    });
  });

  group('NeuraLivingIntelligenceRuntime fresh approval lifecycle', () {
    test('issues only while enabled and reports the active count', () {
      final runtime = NeuraLivingIntelligenceRuntime.create(
        safeModeReader: () => false,
      );
      runtime.setEnabled(true, context: approvedContext);

      final issue = runtime.issueFreshApprovalLease(
        leaseId: 'runtime-lease',
        actionFingerprint: 'sha256:runtime-action',
        capabilityId: 'change_local_plan',
        contextCapsuleId: 'personal',
        deviceId: 'device-a',
        context: approvedContext,
        explicitApproval: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        now: now,
      );

      expect(issue.issued, isTrue);
      expect(runtime.status(now: now).activeFreshApprovalLeases, 1);
    });

    test('disabling runtime revokes outstanding approval', () {
      final runtime = NeuraLivingIntelligenceRuntime.create(
        safeModeReader: () => false,
      );
      runtime.setEnabled(true, context: approvedContext);
      final issue = runtime.issueFreshApprovalLease(
        leaseId: 'runtime-lease',
        actionFingerprint: 'sha256:runtime-action',
        capabilityId: 'change_local_plan',
        contextCapsuleId: 'personal',
        deviceId: 'device-a',
        context: approvedContext,
        explicitApproval: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        now: now,
      );
      final lease = issue.lease!;

      runtime.setEnabled(false, context: approvedContext);

      expect(lease.revoked, isTrue);
      expect(runtime.status(now: now).activeFreshApprovalLeases, 0);
    });

    test('Safe Mode blocks issuance even after runtime activation', () {
      var safeMode = false;
      final runtime = NeuraLivingIntelligenceRuntime.create(
        safeModeReader: () => safeMode,
      );
      runtime.setEnabled(true, context: approvedContext);
      safeMode = true;

      final issue = runtime.issueFreshApprovalLease(
        leaseId: 'runtime-lease',
        actionFingerprint: 'sha256:runtime-action',
        capabilityId: 'change_local_plan',
        contextCapsuleId: 'personal',
        deviceId: 'device-a',
        context: approvedContext,
        explicitApproval: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        now: now,
      );

      expect(issue.outcome, NeuraFreshApprovalOutcome.blockedBySafeMode);
      expect(runtime.status(now: now).activeFreshApprovalLeases, 0);
    });

    test('data wipe clears cloud and fresh approval state together', () async {
      final runtime = NeuraLivingIntelligenceRuntime.create(
        safeModeReader: () => false,
      );
      runtime.setEnabled(true, context: approvedContext);
      runtime.issueFreshApprovalLease(
        leaseId: 'runtime-lease',
        actionFingerprint: 'sha256:runtime-action',
        capabilityId: 'change_local_plan',
        contextCapsuleId: 'personal',
        deviceId: 'device-a',
        context: approvedContext,
        explicitApproval: true,
        capabilityRegistered: true,
        criticalCapability: false,
        involvesMoneyMovement: false,
        now: now,
      );

      await runtime.resetAfterDataWipe();

      expect(runtime.enabled, isFalse);
      expect(runtime.status(now: now).activeFreshApprovalLeases, 0);
      expect(runtime.presenceEngine.isQuiet, isTrue);
    });
  });
}
