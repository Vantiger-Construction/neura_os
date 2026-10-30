import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/dashboard/proactive_banner_service.dart';
import 'package:neuro_companion/dashboard/widgets/proactive_banner_card.dart';
import 'package:neuro_companion/intelligence/capability_registry.dart';
import 'package:neuro_companion/intelligence/models.dart';
import 'package:neuro_companion/intelligence/neura_intelligence_controller.dart';
import 'package:neuro_companion/modules/human/human_prefs.dart';
import 'package:neuro_companion/modules/human/human_prefs_controller.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

import '../helpers/data_wipe_fixture.dart';

class _GreetingService extends ProactiveBannerService {
  _GreetingService(this.banner, DateTime now)
      : super.forTesting(clock: () => now);

  final ProactiveBanner banner;
  final outcomes = <bool>[];
  int shown = 0;

  @override
  Future<ProactiveBanner?> maybeGetBannerOnAppOpen() async => banner;

  @override
  Future<void> recordShown(ProactiveBanner banner) async {
    shown += 1;
  }

  @override
  Future<void> recordOutcome(
      {required ProactiveBanner banner, required bool acted}) async {
    outcomes.add(acted);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 29, 10);

  ProactiveBanner greeting() {
    final candidate = NeuraIntelligenceCandidate(
      id: 'initiative.arrival:fixture',
      capabilityId: NeuraCapabilityRegistry.surfaceSuggestion,
      specialistId: 'initiative.arrival',
      title: 'Welcome back',
      body: 'No catching up required.',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 2)),
      benefit: 0.6,
      urgency: 0.5,
      disruption: 0.2,
      confidence: 0.9,
      evidence: const [],
    );
    return ProactiveBanner(
      kind: ProactiveBannerKind.presence,
      title: candidate.title,
      body: candidate.body,
      candidate: candidate,
      receipt: NeuraDecisionReceipt(
        id: 'fixture-receipt',
        candidateId: candidate.id,
        capabilityId: candidate.capabilityId,
        specialistId: candidate.specialistId,
        evaluatedAt: now,
        outcome: NeuraDecisionOutcome.allow,
        score: 0.8,
        reasons: const [],
        evidenceIds: const [],
        risk: NeuraCapabilityRisk.readOnly,
        requiresApproval: false,
      ),
    );
  }

  for (final revokeLearning in [false, true]) {
    testWidgets(
        revokeLearning
            ? 'revoking learning removes an offered greeting immediately'
            : 'welcome-back has no Open action or synthetic positive outcome',
        (tester) async {
      final fixture = (await tester.runAsync(DataWipeFixture.create))!;
      SafeBoot.instance.safeMode.value = false;
      HumanPrefsController.instance.prefs.value = HumanPrefs.defaults;
      NeuraIntelligenceController.instance.resetForTesting();
      final service = _GreetingService(greeting(), now);
      addTearDown(service.disposeForTesting);
      await tester.runAsync(() => fixture.run(() async {
            await tester.pumpWidget(MaterialApp(
              home: Scaffold(body: ProactiveBannerCard(service: service)),
            ));
            await tester.pump();
            await tester.pump();
            expect(find.text('Welcome back'), findsOneWidget);
            expect(find.text('Open'), findsNothing);
            expect(find.text('Review'), findsNothing);
            expect(service.shown, 1);
            if (revokeLearning) {
              HumanPrefsController.instance.prefs.value =
                  HumanPrefs.defaults.copyWith(allowLearning: false);
              await tester.pump();
              expect(find.text('Welcome back'), findsNothing);
              expect(service.outcomes, isEmpty);
            } else {
              await tester.tap(find.text('Not now'));
              await tester.pump();
              expect(service.outcomes, [false]);
            }
            await tester.pumpWidget(const SizedBox.shrink());
          }));
    });
  }
}
