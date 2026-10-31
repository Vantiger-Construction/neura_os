import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_graph_service.dart';
import 'package:neuro_companion/mirror/screens/mirror_mode_screen.dart';
import 'package:neuro_companion/modules/therapy/therapy_models.dart';
import 'package:neuro_companion/modules/therapy/therapy_reflection_screen.dart';
import 'package:neuro_companion/modules/therapy/therapy_response_store.dart';

import '../helpers/companion_memory_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'reflection and Mirror saves preserve encrypted journals without companion-memory copies',
      (tester) async {
    late CompanionMemoryFixture f;
    await tester
        .runAsync(() async => f = await CompanionMemoryFixture.create());
    const prompt = TherapyPrompt(
        id: 'synthetic-prompt',
        title: 'Synthetic reflection',
        instruction: 'Write a synthetic observation.',
        method: 'CBT');
    await tester.pumpWidget(
        const MaterialApp(home: TherapyReflectionScreen(prompt: prompt)));
    // The initial journal read uses real filesystem I/O. pumpAndSettle
    // advances only the fake clock and can spin on the loading indicator
    // before the host completes that read, especially under CI coverage.
    // Yield real event turns until the observable loading state completes;
    // retain a real-time bound so a genuinely stuck load still fails.
    final loading = Stopwatch()..start();
    while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
      if (loading.elapsed > const Duration(seconds: 10)) {
        fail('The synthetic journal did not finish its initial file read.');
      }
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }
    expect(find.text('Nothing saved yet for this prompt.'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'Synthetic private journal reflection');
    final save = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed! as Future<void> Function();
    await tester.runAsync(() => f.disk.run(save));
    await tester.pumpAndSettle();
    await tester.runAsync(() => f.disk.run(() async {
          final saved = await TherapyResponseStore.I.forPrompt(prompt.id);
          expect(saved.single.text, 'Synthetic private journal reflection');
          expect(await MemoryGraphService.I.recentNodes(), isEmpty);
          final files =
              await Directory('${f.disk.documents.path}/neura_therapy')
                  .list()
                  .where((entry) => entry is File)
                  .cast<File>()
                  .toList();
          expect(files, isNotEmpty);
          for (final file in files) {
            expect(await file.readAsString(),
                isNot(contains('Synthetic private journal reflection')));
          }
          expect(f.disk.networkAttempts, 0);
        }));
    await tester.pumpWidget(const MaterialApp(home: MirrorModeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'Synthetic private Mirror reflection');
    final finish = tester
        .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save check-in locally'))
        .onPressed! as Future<void> Function();
    await tester.runAsync(() => f.disk.run(finish));
    await tester.pumpAndSettle();
    await tester.runAsync(() => f.disk.run(() async {
          final saved =
              await TherapyResponseStore.I.forPrompt('mirror_checkin');
          expect(saved.single.text,
              contains('Synthetic private Mirror reflection'));
          expect(await MemoryGraphService.I.recentNodes(), isEmpty);
          final encrypted = await File(
                  '${f.disk.documents.path}/neura_therapy/responses.jsonl')
              .readAsString();
          expect(encrypted,
              isNot(contains('Synthetic private Mirror reflection')));
        }));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
