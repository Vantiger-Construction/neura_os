import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/intelligence_preferences.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/intelligence/neura_intelligence_controller.dart';
import 'package:neuro_companion/intelligence/suggestion_calibration.dart';
import 'package:neuro_companion/modules/human/human_prefs.dart';
import 'package:neuro_companion/modules/human/human_prefs_controller.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _arrival = 'initiative.arrival';

NeuraDecisionReceipt _receipt({
  String id = 'receipt-1',
  String specialistId = _arrival,
  double score = 0.7,
  NeuraDecisionOutcome outcome = NeuraDecisionOutcome.allow,
}) =>
    NeuraDecisionReceipt(
      id: id,
      candidateId: 'candidate-$id',
      capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
      specialistId: specialistId,
      outcome: outcome,
      risk: NeuraCapabilityRisk.readOnly,
      score: score,
      requiresApproval: false,
      reasons: const [],
      evidenceIds: const [],
      evaluatedAt: DateTime.utc(2026, 11, 13, 9),
    );

void main() {
  group('NeuraCalibrationSources', () {
    test('registry ids are unique and care support is never calibrated', () {
      final ids = NeuraCalibrationSources.specialistIds
          .map((id) => NeuraCalibrationSources.sourceFor(id)!.value)
          .toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(
        NeuraCalibrationSources.sourceFor('opportunity_radar.care_support'),
        isNull,
      );
      expect(
        NeuraCalibrationSources.labelFor('opportunity_radar.care_support'),
        isNull,
      );
      expect(NeuraCalibrationSources.sourceFor('unregistered'), isNull);
    });
  });

  group('NeuraSuggestionCalibration', () {
    late bool allowed;
    late NeuraSuggestionCalibration calibration;
    final shownAt = DateTime.utc(2026, 11, 13, 9);
    final expiresAt = shownAt.add(const Duration(hours: 2));

    setUp(() {
      allowed = true;
      calibration = NeuraSuggestionCalibration(allowed: () => allowed);
    });

    NeuraSuggestionCalibrationEntry? entryFor(String specialistId) {
      for (final entry in calibration.entries(now: shownAt)) {
        if (entry.specialistId == specialistId) return entry;
      }
      return null;
    }

    void offerAndShow(NeuraDecisionReceipt receipt) {
      calibration.offered(receiptId: receipt.id, expiresAt: expiresAt);
      calibration.shown(receipt: receipt, now: shownAt);
    }

    test('an accepted card scores the kernel score as a forecast', () {
      final receipt = _receipt(score: 0.7);
      offerAndShow(receipt);
      calibration.resolved(
        receiptId: receipt.id,
        acted: true,
        now: shownAt.add(const Duration(minutes: 5)),
      );
      final entry = entryFor(_arrival)!;
      expect(entry.label, 'Welcome back');
      expect(entry.summary.scored, 1);
      expect(entry.summary.meanProbability, closeTo(0.7, 1e-12));
      expect(entry.summary.observedFrequency, 1.0);
      expect(entry.summary.meanBrier, closeTo(0.09, 1e-12));
    });

    test('a dismissal resolves the forecast as not accepted', () {
      final receipt = _receipt(score: 0.7);
      offerAndShow(receipt);
      calibration.resolved(
        receiptId: receipt.id,
        acted: false,
        now: shownAt.add(const Duration(minutes: 5)),
      );
      final summary = entryFor(_arrival)!.summary;
      expect(summary.observedFrequency, 0.0);
      expect(summary.meanBrier, closeTo(0.49, 1e-12));
    });

    test('gestures at or after expiry are never scored', () {
      final atExpiry = _receipt(id: 'at');
      final afterExpiry = _receipt(id: 'after');
      offerAndShow(atExpiry);
      offerAndShow(afterExpiry);
      calibration.resolved(receiptId: 'at', acted: true, now: expiresAt);
      calibration.resolved(
        receiptId: 'after',
        acted: false,
        now: expiresAt.add(const Duration(seconds: 1)),
      );
      expect(entryFor(_arrival), isNull);
    });

    test('an unanswered card expires without becoming a rejection', () {
      offerAndShow(_receipt());
      final later = expiresAt.add(const Duration(days: 1));
      expect(calibration.entries(now: later), isEmpty);
    });

    test('only offered, visible, registered cards are forecast', () {
      // Never offered by an evaluation in this session.
      calibration.shown(receipt: _receipt(id: 'stray'), now: shownAt);
      calibration.resolved(receiptId: 'stray', acted: true, now: shownAt);
      // Suppressed by the kernel.
      offerAndShow(
        _receipt(id: 'hidden', outcome: NeuraDecisionOutcome.suppressed),
      );
      calibration.resolved(receiptId: 'hidden', acted: true, now: shownAt);
      // Care support and unregistered specialists.
      for (final specialist in [
        'opportunity_radar.care_support',
        'unregistered',
      ]) {
        final receipt = _receipt(id: specialist, specialistId: specialist);
        offerAndShow(receipt);
        calibration.resolved(receiptId: receipt.id, acted: true, now: shownAt);
      }
      expect(calibration.entries(now: shownAt), isEmpty);
    });

    test('a card shown twice is forecast once', () {
      final receipt = _receipt();
      offerAndShow(receipt);
      calibration.shown(receipt: receipt, now: shownAt);
      calibration.resolved(receiptId: receipt.id, acted: true, now: shownAt);
      calibration.resolved(receiptId: receipt.id, acted: false, now: shownAt);
      expect(entryFor(_arrival)!.summary.scored, 1);
      expect(entryFor(_arrival)!.summary.observedFrequency, 1.0);
    });

    test('closing the gate clears measurements and records nothing', () {
      final first = _receipt(id: 'first');
      offerAndShow(first);
      calibration.resolved(receiptId: first.id, acted: true, now: shownAt);
      final pending = _receipt(id: 'pending');
      offerAndShow(pending);

      allowed = false;
      expect(calibration.entries(now: shownAt), isEmpty);
      final blocked = _receipt(id: 'blocked');
      offerAndShow(blocked);
      calibration.resolved(receiptId: blocked.id, acted: true, now: shownAt);

      allowed = true;
      // The pending forecast was cleared, not resumed.
      calibration.resolved(receiptId: pending.id, acted: true, now: shownAt);
      expect(calibration.entries(now: shownAt), isEmpty);
    });

    test('a clock rollback leaves cards unmeasured without throwing', () {
      final first = _receipt(id: 'first');
      offerAndShow(first);
      calibration.resolved(receiptId: first.id, acted: true, now: shownAt);
      final rolledBack = _receipt(id: 'rolled-back');
      calibration.offered(receiptId: rolledBack.id, expiresAt: expiresAt);
      calibration.shown(
        receipt: rolledBack,
        now: shownAt.subtract(const Duration(minutes: 1)),
      );
      calibration.resolved(
        receiptId: rolledBack.id,
        acted: true,
        now: shownAt,
      );
      expect(entryFor(_arrival)!.summary.scored, 1);
    });

    test('clear revokes pending cards', () {
      final receipt = _receipt();
      offerAndShow(receipt);
      calibration.clear();
      calibration.resolved(receiptId: receipt.id, acted: true, now: shownAt);
      expect(calibration.entries(now: shownAt), isEmpty);
    });
  });

  group('NeuraIntelligenceController calibration wiring', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await NeuraPrefsCache.init();
    });

    setUp(() async {
      await NeuraPrefsCache.prefs.remove('neura.intelligence.state.v1');
      SafeBoot.instance.safeMode.value = false;
      HumanPrefsController.instance.prefs.value = HumanPrefs.defaults;
      NeuraIntelligenceController.instance.resetForTesting();
    });

    tearDown(() {
      SafeBoot.instance.safeMode.value = false;
      HumanPrefsController.instance.prefs.value = HumanPrefs.defaults;
    });

    NeuraIntelligenceCandidate candidate(DateTime now, String id) =>
        NeuraIntelligenceCandidate(
          id: id,
          capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
          specialistId: _arrival,
          title: 'Synthetic title',
          body: 'Synthetic body',
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 2)),
          benefit: 1,
          urgency: 0.8,
          disruption: 0.05,
          confidence: 1,
        );

    Future<NeuraDecisionReceipt> showAndResolve(
      DateTime now,
      String id, {
      required bool acted,
    }) async {
      final controller = NeuraIntelligenceController.instance;
      final result = await controller.evaluateCandidates(
        candidates: [candidate(now, id)],
        now: now,
      );
      final receipt = result.visible.single.receipt;
      await controller.markShown(receipt.id, now: now);
      await controller.recordOutcome(
        receiptId: receipt.id,
        acted: acted,
        now: now.add(const Duration(minutes: 1)),
      );
      return receipt;
    }

    test('shown and accepted cards appear as display-only statistics',
        () async {
      final controller = NeuraIntelligenceController.instance;
      final now = DateTime.utc(2026, 11, 13, 9);
      final receipt = await showAndResolve(now, 'one', acted: true);

      final entries = controller.suggestionCalibration(
        now: now.add(const Duration(minutes: 2)),
      );
      expect(entries, hasLength(1));
      expect(entries.single.specialistId, _arrival);
      expect(entries.single.summary.scored, 1);
      expect(
        entries.single.summary.meanProbability,
        closeTo(receipt.score, 1e-12),
      );
    });

    test('an outcome without a rendered frame is not measured', () async {
      final controller = NeuraIntelligenceController.instance;
      final now = DateTime.utc(2026, 11, 13, 9);
      final result = await controller.evaluateCandidates(
        candidates: [candidate(now, 'unshown')],
        now: now,
      );
      await controller.recordOutcome(
        receiptId: result.visible.single.receipt.id,
        acted: true,
        now: now,
      );
      expect(controller.suggestionCalibration(now: now), isEmpty);
    });

    test('Safe Mode, learning opt-out and proactivity off each clear it',
        () async {
      final controller = NeuraIntelligenceController.instance;
      var now = DateTime.utc(2026, 11, 13, 9);

      await showAndResolve(now, 'safe', acted: true);
      expect(controller.suggestionCalibration(now: now), isNotEmpty);
      SafeBoot.instance.safeMode.value = true;
      expect(controller.calibrationAllowed, isFalse);
      expect(controller.suggestionCalibration(now: now), isEmpty);
      SafeBoot.instance.safeMode.value = false;
      expect(controller.suggestionCalibration(now: now), isEmpty);

      now = now.add(const Duration(hours: 2));
      await showAndResolve(now, 'learning', acted: true);
      expect(controller.suggestionCalibration(now: now), isNotEmpty);
      HumanPrefsController.instance.prefs.value =
          HumanPrefs.defaults.copyWith(allowLearning: false);
      expect(controller.suggestionCalibration(now: now), isEmpty);
      HumanPrefsController.instance.prefs.value = HumanPrefs.defaults;
      expect(controller.suggestionCalibration(now: now), isEmpty);

      now = now.add(const Duration(hours: 2));
      await showAndResolve(now, 'proactivity', acted: true);
      expect(controller.suggestionCalibration(now: now), isNotEmpty);
      await controller.updatePreferences(
        controller.preferences.copyWith(
          proactivityLevel: NeuraProactivityLevel.off,
        ),
      );
      await controller.updatePreferences(
        controller.preferences.copyWith(
          proactivityLevel: NeuraProactivityLevel.balanced,
        ),
      );
      expect(controller.suggestionCalibration(now: now), isEmpty);
    });

    test('clearing history and data wipe clear calibration', () async {
      final controller = NeuraIntelligenceController.instance;
      var now = DateTime.utc(2026, 11, 13, 9);

      await showAndResolve(now, 'history', acted: true);
      expect(controller.suggestionCalibration(now: now), isNotEmpty);
      await controller.clearHistory();
      expect(controller.suggestionCalibration(now: now), isEmpty);

      now = now.add(const Duration(hours: 2));
      await showAndResolve(now, 'wipe', acted: false);
      expect(controller.suggestionCalibration(now: now), isNotEmpty);
      await controller.resetAfterDataWipe();
      expect(controller.suggestionCalibration(now: now), isEmpty);
      controller.resumeAfterDataWipe();
      expect(controller.suggestionCalibration(now: now), isEmpty);
    });

    test('calibration is not persisted with decision history', () async {
      final now = DateTime.utc(2026, 11, 13, 9);
      await showAndResolve(now, 'persist', acted: true);
      final stored = NeuraPrefsCache.prefs.getString(
        'neura.intelligence.state.v1',
      );
      expect(stored, isNotNull);
      expect(stored, isNot(contains('calibration')));
      expect(stored, isNot(contains('brier')));
    });
  });
}
