import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/action_loom.dart';
import 'package:neuro_companion/intelligence/approval_broker.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/modules/quests/quest_store.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    SafeBoot.instance.safeMode.value = false;
    NeuraActionLoom.instance.resumeAfterDataWipe();
    await QuestStore.instance.wipe();
    await NeuraPrefsCache.prefs.remove('neura.action_loom.ledger.v1');
    await NeuraPrefsCache.prefs
        .remove('neura.action_loom.quest_executions.v1');
  });

  test('approved goal draft creates one reversible local quest', () async {
    final now = DateTime.now().toUtc();
    final candidate = NeuraIntelligenceCandidate(
      id: 'loom-goal-${now.microsecondsSinceEpoch}',
      capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
      specialistId: 'action_loom_test',
      title: 'Turn a goal into one next step',
      body: 'Draft a small quest for approval.',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      payload: const {
        'action': 'draft_quest',
        'goal': 'Finish Neura 1.3',
      },
    );
    final receipt = NeuraDecisionReceipt(
      id: 'receipt-${candidate.id}',
      candidateId: candidate.id,
      capabilityId: candidate.capabilityId,
      specialistId: candidate.specialistId,
      outcome: NeuraDecisionOutcome.askApproval,
      risk: NeuraCapabilityRisk.reversibleLocal,
      score: 0.8,
      requiresApproval: true,
      reasons: const ['Explicit approval required.'],
      evidenceIds: const [],
      evaluatedAt: now,
    );

    final loom = NeuraActionLoom.instance;
    final pending = await loom.submit(
      NeuraCouncilDecision(candidate: candidate, receipt: receipt),
    );
    expect(pending.status, NeuraApprovalStatus.pendingApproval);
    expect(await QuestStore.instance.getQuests(), isEmpty);

    final approved = await loom.approve(pending.id);
    final executed = await loom.execute(approved.id);
    expect(executed.status, NeuraApprovalStatus.executed);
    expect(await QuestStore.instance.getQuests(), hasLength(1));

    final undone = await loom.undo(executed.id);
    expect(undone.status, NeuraApprovalStatus.undone);
    expect(await QuestStore.instance.getQuests(), isEmpty);
  });

  test('undo refuses to erase a quest that already has progress', () async {
    final now = DateTime.now().toUtc();
    final candidate = NeuraIntelligenceCandidate(
      id: 'loom-progress-${now.microsecondsSinceEpoch}',
      capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
      specialistId: 'action_loom_test',
      title: 'Turn a goal into one next step',
      body: 'Draft a small quest for approval.',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      payload: const {
        'action': 'draft_quest',
        'goal': 'Protect completed work',
      },
    );
    final receipt = NeuraDecisionReceipt(
      id: 'receipt-${candidate.id}',
      candidateId: candidate.id,
      capabilityId: candidate.capabilityId,
      specialistId: candidate.specialistId,
      outcome: NeuraDecisionOutcome.askApproval,
      risk: NeuraCapabilityRisk.reversibleLocal,
      score: 0.8,
      requiresApproval: true,
      reasons: const ['Explicit approval required.'],
      evidenceIds: const [],
      evaluatedAt: now,
    );

    final loom = NeuraActionLoom.instance;
    final pending = await loom.submit(
      NeuraCouncilDecision(candidate: candidate, receipt: receipt),
    );
    final approved = await loom.approve(pending.id);
    final executed = await loom.execute(approved.id);
    final questId = executed.executionResult!.value! as String;
    await QuestStore.instance.markDoneToday(questId);

    final refused = await loom.undo(executed.id);

    expect(refused.status, NeuraApprovalStatus.executed);
    expect(refused.failure, contains('progress'));
    expect(
      (await QuestStore.instance.getQuests()).map((quest) => quest.id),
      contains(questId),
    );
    expect(
      (await QuestStore.instance.getDone()).map((done) => done.questId),
      contains(questId),
    );
  });

  test('durable ledgers store consent metadata without raw goal text', () async {
    final now = DateTime.now().toUtc();
    final candidate = NeuraIntelligenceCandidate(
      id: 'loom-audit-${now.microsecondsSinceEpoch}',
      capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
      specialistId: 'action_loom_test',
      title: 'Private goal action',
      body: 'Review locally.',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      payload: const {
        'action': 'draft_quest',
        'goal': 'PRIVATE_GOAL_MUST_NOT_ENTER_AUDIT',
      },
    );
    final receipt = NeuraDecisionReceipt(
      id: 'receipt-${candidate.id}',
      candidateId: candidate.id,
      capabilityId: candidate.capabilityId,
      specialistId: candidate.specialistId,
      outcome: NeuraDecisionOutcome.askApproval,
      risk: NeuraCapabilityRisk.reversibleLocal,
      score: 0.8,
      requiresApproval: true,
      reasons: const ['Explicit approval required.'],
      evidenceIds: const [],
      evaluatedAt: now,
    );

    final pending = await NeuraActionLoom.instance.submit(
      NeuraCouncilDecision(candidate: candidate, receipt: receipt),
    );
    final approved = await NeuraActionLoom.instance.approve(pending.id);
    await NeuraActionLoom.instance.execute(approved.id);

    final audit = NeuraPrefsCache.prefs
        .getString('neura.action_loom.ledger.v1')!;
    final executions = NeuraPrefsCache.prefs
        .getString('neura.action_loom.quest_executions.v1')!;
    expect(audit, contains('explicit_user_approval'));
    expect(audit, contains('executed'));
    expect(audit, isNot(contains('PRIVATE_GOAL_MUST_NOT_ENTER_AUDIT')));
    expect(executions, isNot(contains('PRIVATE_GOAL_MUST_NOT_ENTER_AUDIT')));
  });

  test('data wipe revokes raw proposals and suspends ledger writes', () async {
    final now = DateTime.now().toUtc();
    final candidate = NeuraIntelligenceCandidate(
      id: 'loom-wipe-${now.microsecondsSinceEpoch}',
      capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
      specialistId: 'action_loom_test',
      title: 'Private proposal',
      body: 'RAW_PRIVATE_PROPOSAL',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      payload: const {
        'action': 'draft_quest',
        'goal': 'RAW_PRIVATE_WIPE_GOAL',
      },
    );
    final receipt = NeuraDecisionReceipt(
      id: 'receipt-${candidate.id}',
      candidateId: candidate.id,
      capabilityId: candidate.capabilityId,
      specialistId: candidate.specialistId,
      outcome: NeuraDecisionOutcome.askApproval,
      risk: NeuraCapabilityRisk.reversibleLocal,
      score: 0.8,
      requiresApproval: true,
      reasons: const ['Explicit approval required.'],
      evidenceIds: const [],
      evaluatedAt: now,
    );
    final loom = NeuraActionLoom.instance;
    final pending = await loom.submit(
      NeuraCouncilDecision(candidate: candidate, receipt: receipt),
    );

    await loom.resetAfterDataWipe();

    expect(loom.broker.actions, isEmpty);
    expect(loom.broker.find(pending.id), isNull);
    await expectLater(loom.approve(pending.id), throwsStateError);
    loom.resumeAfterDataWipe();
  });

  test('replay after a pruned execution ledger cannot duplicate a quest',
      () async {
    final now = DateTime.now().toUtc();
    final candidate = NeuraIntelligenceCandidate(
      id: 'loom-replay-${now.microsecondsSinceEpoch}',
      capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
      specialistId: 'action_loom_test',
      title: 'Idempotent proposal',
      body: 'Create exactly one deterministic quest.',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      payload: const {
        'action': 'draft_quest',
        'goal': 'Never duplicate this quest',
      },
    );
    final receipt = NeuraDecisionReceipt(
      id: 'receipt-${candidate.id}',
      candidateId: candidate.id,
      capabilityId: candidate.capabilityId,
      specialistId: candidate.specialistId,
      outcome: NeuraDecisionOutcome.askApproval,
      risk: NeuraCapabilityRisk.reversibleLocal,
      score: 0.8,
      requiresApproval: true,
      reasons: const ['Explicit approval required.'],
      evidenceIds: const [],
      evaluatedAt: now,
    );
    final decision = NeuraCouncilDecision(
      candidate: candidate,
      receipt: receipt,
    );
    final loom = NeuraActionLoom.instance;
    final firstPending = await loom.submit(decision);
    final firstApproved = await loom.approve(firstPending.id);
    final firstExecuted = await loom.execute(firstApproved.id);
    final questId = firstExecuted.executionResult!.value! as String;

    await NeuraPrefsCache.prefs.remove(
      'neura.action_loom.quest_executions.v1',
    );
    await loom.resetApprovalCacheForTesting();

    final replayPending = await loom.submit(decision);
    final replayApproved = await loom.approve(replayPending.id);
    final replayed = await loom.execute(replayApproved.id);
    final matching = (await QuestStore.instance.getQuests())
        .where((quest) => quest.id == questId)
        .toList(growable: false);

    expect(replayed.status, NeuraApprovalStatus.executed);
    expect(matching, hasLength(1));
  });
}
