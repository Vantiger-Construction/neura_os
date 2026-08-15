import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/autonomy_kernel.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 14, 18);

  group('NeuraAutonomyKernel attention boundaries', () {
    test('suppresses candidates in Safe Mode', () {
      final receipt = NeuraAutonomyKernel().evaluate(
        candidate: _candidate(now: now),
        policy: _policy(safeMode: true),
        now: now,
      );

      expect(receipt.outcome, NeuraDecisionOutcome.suppressed);
      expect(_hasReason(receipt, 'Safe Mode'), isTrue);
    });

    test('suppresses candidates during quiet hours', () {
      final receipt = NeuraAutonomyKernel().evaluate(
        candidate: _candidate(now: now),
        policy: _policy(quietHours: true),
        now: now,
      );

      expect(receipt.outcome, NeuraDecisionOutcome.suppressed);
      expect(_hasReason(receipt, 'quiet hours'), isTrue);
    });

    test('protects deep focus from non-urgent candidates', () {
      final receipt = NeuraAutonomyKernel().evaluate(
        candidate: _candidate(now: now, urgency: 0.7),
        policy: _policy(focusMode: 'deepWork'),
        now: now,
      );

      expect(receipt.outcome, NeuraDecisionOutcome.suppressed);
      expect(_hasReason(receipt, 'deepWork'), isTrue);
    });

    test('enforces the user-controlled daily suggestion cap', () {
      final receipt = NeuraAutonomyKernel().evaluate(
        candidate: _candidate(now: now),
        policy: _policy(maxDailySuggestions: 3, suggestionsToday: 3),
        now: now,
      );

      expect(receipt.outcome, NeuraDecisionOutcome.suppressed);
      expect(_hasReason(receipt, 'daily suggestion limit'), isTrue);
    });
  });

  group('NeuraAutonomyKernel privacy and capability boundaries', () {
    test('suppresses sensitive evidence when the user has not allowed it', () {
      final receipt = NeuraAutonomyKernel().evaluate(
        candidate: _candidate(
          now: now,
          evidence: [_evidence(now, sensitivity: NeuraSensitivity.sensitive)],
        ),
        policy: _policy(allowSensitiveSignals: false),
        now: now,
      );

      expect(receipt.outcome, NeuraDecisionOutcome.suppressed);
      expect(_hasReason(receipt, 'sensitive evidence'), isTrue);
      expect(receipt.evidenceIds, isEmpty);
    });

    test('blocks unknown capabilities by default', () {
      final receipt = NeuraAutonomyKernel().evaluate(
        candidate: _candidate(
          now: now,
          capabilityId: 'unregistered_side_effect',
        ),
        policy: _policy(),
        now: now,
      );

      expect(receipt.outcome, NeuraDecisionOutcome.blocked);
      expect(receipt.risk, NeuraCapabilityRisk.critical);
      expect(receipt.requiresApproval, isFalse);
      expect(_hasReason(receipt, 'blocks this capability'), isTrue);
    });

    test('requires fresh approval for local plan changes', () {
      final receipt = NeuraAutonomyKernel().evaluate(
        candidate: _candidate(
          now: now,
          capabilityId: NeuraCapabilityRegistry.changeLocalPlan,
          benefit: 1,
          urgency: 1,
          disruption: 0,
          confidence: 1,
        ),
        policy: _policy(),
        now: now,
      );

      expect(receipt.outcome, NeuraDecisionOutcome.askApproval);
      expect(receipt.requiresApproval, isTrue);
      expect(receipt.risk, NeuraCapabilityRisk.reversibleLocal);
      expect(_hasReason(receipt, 'fresh user confirmation'), isTrue);
    });
  });

  test('returns a deterministic, explainable score and evidence trail', () {
    final receipt = NeuraAutonomyKernel(
      receiptIdFactory: (candidate, evaluatedAt) =>
          'receipt:${candidate.id}:${evaluatedAt.toIso8601String()}',
    ).evaluate(
      candidate: _candidate(
        now: now,
        benefit: 0.8,
        confidence: 0.75,
        urgency: 0.5,
        disruption: 0.25,
        evidence: [_evidence(now)],
      ),
      policy: _policy(),
      now: now,
    );

    // 0.8*0.36 + 0.75*0.24 + 0.5*0.24 - 0.25*0.28 = 0.518.
    expect(receipt.score, closeTo(0.518, 0.000001));
    expect(receipt.outcome, NeuraDecisionOutcome.allow);
    expect(receipt.requiresApproval, isFalse);
    expect(receipt.id, 'receipt:candidate-1:${now.toIso8601String()}');
    expect(receipt.evidenceIds, ['evidence-1']);
    expect(_hasReason(receipt, 'test.specialist supplied'), isTrue);
    expect(_hasReason(receipt, 'readOnly'), isTrue);
    expect(
        _hasReason(receipt, 'passed privacy, attention, and consent'), isTrue);
  });
}

NeuraAutonomyPolicy _policy({
  bool enabled = true,
  bool allowSensitiveSignals = true,
  int maxDailySuggestions = 5,
  int suggestionsToday = 0,
  int suggestionsLastHour = 0,
  String focusMode = 'normal',
  bool safeMode = false,
  bool recentlyDeclined = false,
  bool quietHours = false,
}) =>
    NeuraAutonomyPolicy(
      enabled: enabled,
      allowSensitiveSignals: allowSensitiveSignals,
      maxDailySuggestions: maxDailySuggestions,
      suggestionsToday: suggestionsToday,
      suggestionsLastHour: suggestionsLastHour,
      focusMode: focusMode,
      safeMode: safeMode,
      recentlyDeclined: recentlyDeclined,
      quietHours: quietHours,
    );

NeuraIntelligenceCandidate _candidate({
  required DateTime now,
  String capabilityId = NeuraCapabilityRegistry.surfaceSuggestion,
  double benefit = 0.9,
  double urgency = 0.8,
  double disruption = 0.1,
  double confidence = 0.9,
  List<NeuraEvidenceRef> evidence = const [],
}) =>
    NeuraIntelligenceCandidate(
      id: 'candidate-1',
      capabilityId: capabilityId,
      specialistId: 'test.specialist',
      title: 'Test opportunity',
      body: 'A deterministic local candidate.',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      evidence: evidence,
      benefit: benefit,
      urgency: urgency,
      disruption: disruption,
      confidence: confidence,
    );

NeuraEvidenceRef _evidence(
  DateTime now, {
  NeuraSensitivity sensitivity = NeuraSensitivity.routine,
}) =>
    NeuraEvidenceRef(
      id: 'evidence-1',
      source: 'test',
      summary: 'A local, explainable signal.',
      observedAt: now,
      confidence: 0.9,
      sensitivity: sensitivity,
    );

bool _hasReason(NeuraDecisionReceipt receipt, String fragment) =>
    receipt.reasons
        .any((reason) => reason.toLowerCase().contains(fragment.toLowerCase()));
