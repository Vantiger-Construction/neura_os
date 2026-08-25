import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/intelligence_preferences.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/intelligence/neura_intelligence_controller.dart';
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
    await NeuraPrefsCache.prefs.remove('neura.intelligence.state.v1');
    SafeBoot.instance.safeMode.value = false;
    NeuraIntelligenceController.instance.resetForTesting();
  });

  test('records and updates an explainable suggestion lifecycle', () async {
    final now = DateTime.utc(2026, 8, 14, 18);
    final controller = NeuraIntelligenceController.instance;
    final result = await controller.evaluateCandidates(
      candidates: [_candidate(now)],
      now: now,
    );

    expect(result.visible, hasLength(1));
    final receipt = result.visible.single.receipt;
    expect(controller.records, hasLength(1));

    await controller.markShown(receipt.id);
    expect(
      controller.records.single.receipt.userOutcome,
      NeuraSuggestionOutcome.shown,
    );

    await controller.recordOutcome(receiptId: receipt.id, acted: true);
    await controller.recordOutcome(receiptId: receipt.id, acted: false);
    expect(
      controller.records.single.receipt.userOutcome,
      NeuraSuggestionOutcome.acted,
    );
  });

  test('does not persist private suggestion title or body', () async {
    final controller = NeuraIntelligenceController.instance;
    final now = DateTime.utc(2026, 8, 14, 18);
    await controller.evaluateCandidates(
      candidates: [_candidate(now)],
      now: now,
    );

    final stored = NeuraPrefsCache.prefs.getString(
      'neura.intelligence.state.v1',
    );
    expect(stored, isNotNull);
    expect(stored, isNot(contains('Private title')));
    expect(stored, isNot(contains('Private recommendation body')));
    expect(stored, contains('surface_local_suggestion'));
  });

  test('quiet hours suppress a candidate before it reaches the UI', () async {
    final controller = NeuraIntelligenceController.instance;
    await controller.updatePreferences(
      const NeuraIntelligencePreferences(
        quietHoursEnabled: true,
        quietHoursStart: 22,
        quietHoursEnd: 7,
      ),
    );
    final now = DateTime(2026, 8, 14, 23);
    final result = await controller.evaluateCandidates(
      candidates: [_candidate(now)],
      now: now,
    );

    expect(result.visible, isEmpty);
    expect(
      controller.records.single.receipt.outcome,
      NeuraDecisionOutcome.suppressed,
    );
    expect(
      controller.records.single.receipt.reasons.join(' '),
      contains('quiet hours'),
    );
  });
}

NeuraIntelligenceCandidate _candidate(DateTime now) =>
    NeuraIntelligenceCandidate(
      id: 'controller-candidate',
      capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
      specialistId: 'controller_test',
      title: 'Private title',
      body: 'Private recommendation body',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      benefit: 1,
      urgency: 0.8,
      disruption: 0.05,
      confidence: 1,
    );
