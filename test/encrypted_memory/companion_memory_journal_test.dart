import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_graph_service.dart';
import 'package:neuro_companion/mirror/screens/mirror_mode_screen.dart';
import 'package:neuro_companion/modules/therapy/therapy_models.dart';
import 'package:neuro_companion/modules/therapy/therapy_reflection_screen.dart';
import 'package:neuro_companion/modules/therapy/therapy_response_store.dart';

import '../helpers/companion_memory_fixture.dart';

Future<void> pumpUntilVisible(WidgetTester tester, Finder finder) async {
  for (var attempt = 0;
      attempt < 100 && finder.evaluate().isEmpty;
      attempt += 1) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
}

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
    // The reflection screen keeps an indeterminate progress indicator while
    // its local journal is loading. The test only needs the editor and save
    // callback, so do not wait for the animation to settle.
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'Synthetic private journal reflection');
    final save = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed! as Future<void> Function();
    await tester.runAsync(() => f.disk.run(save));
    await tester.pump();
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
    await pumpUntilVisible(tester, find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'Synthetic private Mirror reflection');
    final finish = tester
        .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save check-in locally'))
        .onPressed! as Future<void> Function();
    await tester.runAsync(() => f.disk.run(finish));
    await tester.pump();
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
