import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/action_loom.dart';
import 'package:neuro_companion/intelligence/approval_broker.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/fresh_approval_lease.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/modules/quests/quest_store.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

NeuraCouncilDecision _decision(String id, {required String goal}) {
  final now = DateTime.now().toUtc();
  final candidate = NeuraIntelligenceCandidate(
    id: id,
    capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
    specialistId: 'fresh_approval_test',
    title: 'Create one reviewed local quest',
    body: 'This mutation needs a fresh approval lease.',
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
    payload: {
      'action': 'draft_quest',
      'goal': goal,
    },
  );
  return NeuraCouncilDecision(
    candidate: candidate,
    receipt: NeuraDecisionReceipt(
      id: 'receipt-$id',
      candidateId: id,
      capabilityId: candidate.capabilityId,
      specialistId: candidate.specialistId,
      outcome: NeuraDecisionOutcome.askApproval,
      risk: NeuraCapabilityRisk.reversibleLocal,
      score: 0.9,
      requiresApproval: true,
      reasons: const <String>['Explicit approval required.'],
      evidenceIds: const <String>[],
      evaluatedAt: now,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    SafeBoot.instance.safeMode.value = false;
    NeuraActionLoom.instance.resumeAfterDataWipe();
    await QuestStore.instance.wipe();
    await NeuraPrefsCache.prefs.remove('neura.action_loom.ledger.v1');
    await NeuraPrefsCache.prefs.remove(
      'neura.action_loom.quest_executions.v1',
    );
  });

  test('lease is active after approval and consumed before mutation', () async {
    final loom = NeuraActionLoom.instance;
    final decision = _decision(
      'fresh-execute-${DateTime.now().microsecondsSinceEpoch}',
      goal: 'PROTECTED_GOAL_MUST_NOT_ENTER_AUDIT',
    );
    final pending = await loom.submit(decision);
    final approved = await loom.approve(pending.id);
    final active = loom.freshApprovalMetadataForTesting(approved.id);

    expect(approved.status, NeuraApprovalStatus.approved);
    expect(active, isNotNull);
    expect(active!.state, NeuraFreshApprovalLeaseState.active);

    final executed = await loom.execute(approved.id);
    final consumed = loom.freshApprovalMetadataForTesting(approved.id);
    final audit =
        NeuraPrefsCache.prefs.getString('neura.action_loom.ledger.v1')!;

    expect(executed.status, NeuraApprovalStatus.executed);
    expect(consumed, isNotNull);
    expect(consumed!.state, NeuraFreshApprovalLeaseState.consumed);
    expect(consumed.consumedAtUtc, isNotNull);
    expect(await QuestStore.instance.getQuests(), hasLength(1));
    expect(audit, contains('"fresh_approval_state":"consumed"'));
    expect(audit, isNot(contains('PROTECTED_GOAL_MUST_NOT_ENTER_AUDIT')));
  });

  test('direct broker approval cannot bypass Action Loom lease issuance',
      () async {
    final loom = NeuraActionLoom.instance;
    final decision = _decision(
      'fresh-approve-bypass-${DateTime.now().microsecondsSinceEpoch}',
      goal: 'Do not create this quest',
    );
    final pending = await loom.submit(decision);
    final bypassApproved = loom.broker.approve(pending.id);

    final denied = await loom.execute(bypassApproved.id);

    expect(denied.status, NeuraApprovalStatus.denied);
    expect(denied.denialReason, contains('fresh approval'));
    expect(await QuestStore.instance.getQuests(), isEmpty);
  });

  test('direct broker execution cannot use a legitimate Action Loom lease',
      () async {
    final loom = NeuraActionLoom.instance;
    final decision = _decision(
      'fresh-execute-bypass-${DateTime.now().microsecondsSinceEpoch}',
      goal: 'Do not bypass the Action Loom execution boundary',
    );
    final pending = await loom.submit(decision);
    final approved = await loom.approve(pending.id);
    final active = loom.freshApprovalMetadataForTesting(approved.id);

    final bypassed = await loom.broker.execute(approved.id);
    final after = loom.freshApprovalMetadataForTesting(approved.id);

    expect(active, isNotNull);
    expect(active!.state, NeuraFreshApprovalLeaseState.active);
    expect(bypassed.status, NeuraApprovalStatus.failed);
    expect(bypassed.failure, contains('StateError'));
    expect(after, isNotNull);
    expect(after!.state, NeuraFreshApprovalLeaseState.active);
    expect(await QuestStore.instance.getQuests(), isEmpty);
  });

  test('lease too close to expiry is rejected before execution begins',
      () async {
    final loom = NeuraActionLoom.instance;
    final decision = _decision(
      'fresh-short-${DateTime.now().microsecondsSinceEpoch}',
      goal: 'Do not race the approval clock',
    );
    final pending = await loom.submit(decision);
    final approved = await loom.approve(
      pending.id,
      freshApprovalLifetime: const Duration(seconds: 4),
    );

    final denied = await loom.execute(approved.id);

    expect(denied.status, NeuraApprovalStatus.denied);
    expect(denied.denialReason, contains('too close to expiry'));
    expect(await QuestStore.instance.getQuests(), isEmpty);
  });

  test('Safe Mode hold does not leak an executor authorization', () async {
    final loom = NeuraActionLoom.instance;
    final decision = _decision(
      'fresh-safe-mode-${DateTime.now().microsecondsSinceEpoch}',
      goal: 'Run only after Safe Mode is disabled',
    );
    final pending = await loom.submit(decision);
    final approved = await loom.approve(pending.id);
    SafeBoot.instance.safeMode.value = true;

    final held = await loom.execute(approved.id);
    final whileHeld = loom.freshApprovalMetadataForTesting(approved.id);

    expect(held.status, NeuraApprovalStatus.policyHeld);
    expect(held.policyReason, contains('Safe Mode'));
    expect(whileHeld, isNotNull);
    expect(whileHeld!.state, NeuraFreshApprovalLeaseState.active);
    expect(await QuestStore.instance.getQuests(), isEmpty);

    SafeBoot.instance.safeMode.value = false;
    final executed = await loom.execute(approved.id);

    expect(executed.status, NeuraApprovalStatus.executed);
    expect(
      loom.freshApprovalStateForTesting(approved.id),
      NeuraFreshApprovalLeaseState.consumed,
    );
    expect(await QuestStore.instance.getQuests(), hasLength(1));
  });

  test('explicit denial revokes unused approval evidence', () async {
    final loom = NeuraActionLoom.instance;
    final decision = _decision(
      'fresh-deny-${DateTime.now().microsecondsSinceEpoch}',
      goal: 'Do not run after denial',
    );
    final pending = await loom.submit(decision);
    final approved = await loom.approve(pending.id);

    final denied = await loom.deny(approved.id);

    expect(denied.status, NeuraApprovalStatus.denied);
    expect(
      loom.freshApprovalStateForTesting(approved.id),
      NeuraFreshApprovalLeaseState.revoked,
    );
    expect(await QuestStore.instance.getQuests(), isEmpty);
  });

  test('local-data wipe clears all process-local approval leases', () async {
    final loom = NeuraActionLoom.instance;
    final decision = _decision(
      'fresh-wipe-${DateTime.now().microsecondsSinceEpoch}',
      goal: 'Clear this approval evidence',
    );
    final pending = await loom.submit(decision);
    final approved = await loom.approve(pending.id);
    expect(loom.freshApprovalRecordCountForTesting, 1);

    await loom.resetAfterDataWipe();

    expect(loom.freshApprovalRecordCountForTesting, 0);
    expect(
      loom.freshApprovalStateForTesting(approved.id),
      NeuraFreshApprovalLeaseState.missing,
    );
    loom.resumeAfterDataWipe();
  });
}
