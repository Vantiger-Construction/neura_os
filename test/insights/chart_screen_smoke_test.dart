import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/insights/screens/weekly_snapshot_screen.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/recap/screens/neura_recap_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DataWipeFixture fixture;
  setUp(() async {
    fixture = await DataWipeFixture.create();
  });

  for (final screen in ['Weekly Snapshot', 'Recap']) {
    for (final samples in [0, 1, 4]) {
      testWidgets(
          '$screen renders $samples synthetic samples and handles chart input',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 1800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await fixture.run(() async {
          SafeBoot.instance.safeMode.value = false;
          SafeBoot.instance.restartRequired.value = false;
          await tester.runAsync(() async {
            final crypto = await MemoryCrypto.demo();
            final now = DateTime.now();
            final entries = [
              for (var i = 0; i < samples; i++)
                MoodEntry(
                    timestamp: now.subtract(Duration(hours: i + 1)),
                    mood0to10: i.isEven ? 0 : 10,
                    note: 'Synthetic chart sample'),
            ];
            final encrypted = await crypto.encryptJson(
                {'items': entries.map((e) => e.toJson()).toList()});
            await NeuraPrefsCache.prefs
                .setString('neura_mood_entries_v1', encrypted);
          });
          await tester.pumpWidget(MaterialApp(
              home: screen == 'Recap'
                  ? const NeuraRecapScreen()
                  : const WeeklySnapshotScreen()));
          // Drain real file reads between virtual UI frames. A loading
          // failure must be bounded instead of leaving an endless spinner.
          for (var i = 0; i < 25; i++) {
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 40));
            });
            await tester.pump();
            if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
              break;
            }
          }
          expect(find.byType(CircularProgressIndicator), findsNothing);
          await tester.pumpAndSettle();
          final chart = find.byType(LineChart);
          expect(chart, samples < 2 ? findsNothing : findsOneWidget);
          if (samples >= 2) {
            await tester.ensureVisible(chart);
            final bounds = tester.getRect(chart);
            final mouse =
                await tester.createGesture(kind: PointerDeviceKind.mouse);
            await mouse.addPointer(location: bounds.center);
            for (final offset in [-80.0, 0.0, 80.0, 0.0]) {
              await mouse.moveTo(bounds.center + Offset(offset, 0));
              await tester.pump();
              await tester.tapAt(bounds.center + Offset(offset, 0));
              await tester.pump();
            }
            await mouse.removePointer();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          fixture.expectIsolation();
        });
      }, timeout: const Timeout(Duration(seconds: 30)));
    }
  }
}
