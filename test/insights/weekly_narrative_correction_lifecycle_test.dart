import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/insights/services/weekly_summarist_service.dart';

import '../helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DataWipeFixture disk;
  setUp(() async {
    disk = await DataWipeFixture.create();
  });

  for (final sameChoice in [false, true]) {
    test(
        'newer feedback survives an older draft (same choice: $sameChoice)',
        () => disk.run(() async {
              final entered = Completer<void>();
              final response = Completer<String>();
              final service =
                  WeeklySummaristService.forTesting(draft: (prompt) {
                expect(prompt,
                    contains(WeeklyNarrativeCorrection.tooHarsh.guidance));
                entered.complete();
                return response.future;
              });
              await service
                  .recordCorrection(WeeklyNarrativeCorrection.tooHarsh);
              final generating = service.maybeGenerateOnAppOpen();
              await entered.future;
              await service.recordCorrection(WeeklyNarrativeCorrection.tooLong);
              if (sameChoice) {
                await service
                    .recordCorrection(WeeklyNarrativeCorrection.tooHarsh);
              }
              response.complete('A fictional weekly reflection.');
              await generating;
              expect(
                  service.pendingCorrection,
                  sameChoice
                      ? WeeklyNarrativeCorrection.tooHarsh
                      : WeeklyNarrativeCorrection.tooLong);
              expect(disk.networkAttempts, 0);
              disk.expectIsolation();
            }));
  }

  test(
      'a refused draft save does not consume feedback',
      () => disk.run(() async {
            final service = WeeklySummaristService.forTesting(
                draft: (_) async => 'A fictional weekly reflection.');
            await service.recordCorrection(WeeklyNarrativeCorrection.tooHarsh);
            disk.preferences.refusedWrites
                .add('flutter.neura.weekly_summarist_state.v1');
            await service.maybeGenerateOnAppOpen();
            expect(
                service.pendingCorrection, WeeklyNarrativeCorrection.tooHarsh);
            expect(disk.networkAttempts, 0);
            disk.expectIsolation();
          }));

  test(
      'a refused correction save reports failure and preserves durable feedback',
      () => disk.run(() async {
            final service =
                WeeklySummaristService.forTesting(draft: (_) async => 'Unused');
            await service.recordCorrection(WeeklyNarrativeCorrection.tooHarsh);
            disk.preferences.refusedWrites
                .add('flutter.neura.weekly_summarist_correction.v1');
            await expectLater(
                service.recordCorrection(WeeklyNarrativeCorrection.tooLong),
                throwsStateError);
            expect(
                service.pendingCorrection, WeeklyNarrativeCorrection.tooHarsh);
            disk.expectIsolation();
          }));

  test(
      'a failed draft retains feedback without making a cloud request',
      () => disk.run(() async {
            final service = WeeklySummaristService.forTesting(
                draft: (_) async =>
                    throw StateError('Synthetic draft failure'));
            await service.recordCorrection(WeeklyNarrativeCorrection.tooLong);
            await service.maybeGenerateOnAppOpen();
            expect(
                service.pendingCorrection, WeeklyNarrativeCorrection.tooLong);
            expect(disk.networkAttempts, 0);
            disk.expectIsolation();
          }));
}
