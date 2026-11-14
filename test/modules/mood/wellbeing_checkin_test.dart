import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/mood/mood_checkin_screen.dart';
import 'package:neuro_companion/modules/mood/mood_history_screen.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 14, 12);
  MoodEntry entry({int mood = 5, int? energy, double? sleep, DateTime? at}) =>
      MoodEntry(
          timestamp: at ?? now,
          mood0to10: mood,
          note: 'Synthetic note',
          energy0to10: energy,
          sleepHours: sleep);

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test('old entries remain readable and absent metadata stays absent', () {
    final old = {
      'ts': now.toUtc().toIso8601String(),
      'mood': 4,
      'note': 'Synthetic legacy note'
    };
    final decoded = MoodEntry.fromJson(old);
    expect(decoded.energy0to10, isNull);
    expect(decoded.sleepHours, isNull);
    expect(decoded.toJson(), old);
  });
  test('optional metadata round trips including genuine zero measurements', () {
    final decoded = MoodEntry.decodeList(
        MoodEntry.encodeList([entry(energy: 0, sleep: 0)]));
    expect(decoded.single.energy0to10, 0);
    expect(decoded.single.sleepHours, 0);
  });
  test('new values reject out of range and nonfinite input', () {
    for (final sleep in [-1.0, 24.5, double.nan, double.infinity]) {
      expect(() => entry(sleep: sleep), throwsArgumentError);
    }
    expect(() => entry(energy: 11), throwsArgumentError);
    expect(() => entry(energy: -1), throwsArgumentError);
    final decoded = MoodEntry.fromJson(
        {...entry().toJson(), 'energy': 2.5, 'sleepHours': 'unknown'});
    expect(decoded.mood0to10, 5);
    expect(decoded.energy0to10, isNull);
    expect(decoded.sleepHours, isNull);
  });
  test('summary excludes missing optional values, older and future entries',
      () {
    final summary = MoodSummary([
      entry(mood: 2),
      entry(mood: 8, energy: 6, sleep: 7.5),
      entry(
          mood: 10,
          energy: 10,
          sleep: 20,
          at: now.subtract(const Duration(days: 8))),
      entry(mood: 10, at: now.add(const Duration(seconds: 1))),
    ], now);
    expect(summary.count, 2);
    expect(summary.moodAverage, 5);
    expect(summary.energyAverage, 6);
    expect(summary.energyCount, 1);
    expect(summary.sleepAverage, 7.5);
    expect(summary.sleepCount, 1);
    expect(MoodSummary([], now).moodAverage, isNull);
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(850, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
  }

  testWidgets('optional fields require explicit inclusion and save',
      (tester) async {
    MoodEntry? saved;
    await pump(tester, MoodCheckInScreen(save: (value) async {
      saved = value;
    }));
    expect(find.byKey(const ValueKey('energy-slider')), findsNothing);
    expect(find.byKey(const ValueKey('sleep-slider')), findsNothing);
    expect(saved, isNull);
    await tester.tap(find.text('Include energy (optional)'));
    await tester.pump();
    await tester.tap(find.text('Include sleep (optional)'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save check-in'));
    await tester.tap(find.text('Save check-in'));
    await tester.pump();
    expect(saved!.energy0to10, 5);
    expect(saved!.sleepHours, 8);
  });
  testWidgets('unchecked energy and sleep are not saved as defaults',
      (tester) async {
    MoodEntry? saved;
    await pump(tester, MoodCheckInScreen(save: (entry) async {
      saved = entry;
    }));
    await tester.ensureVisible(find.text('Save check-in'));
    await tester.tap(find.text('Save check-in'));
    await tester.pump();
    expect(saved!.energy0to10, isNull);
    expect(saved!.sleepHours, isNull);
  });

  testWidgets('leaving during an admitted save cannot pop a newer route',
      (tester) async {
    final pending = Completer<void>();
    await pump(tester, MoodCheckInScreen(save: (_) => pending.future));
    await tester.enterText(find.byType(TextField), 'Synthetic draft');
    await tester.ensureVisible(find.text('Save check-in'));
    await tester.tap(find.text('Save check-in'));
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('New route'))));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('New route'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  testWidgets('save failure keeps draft and enables retry', (tester) async {
    var attempts = 0;
    await pump(tester, MoodCheckInScreen(save: (_) async {
      attempts++;
      throw StateError('synthetic failure');
    }));
    await tester.enterText(find.byType(TextField), 'Synthetic draft');
    await tester.ensureVisible(find.text('Save check-in'));
    await tester.tap(find.text('Save check-in'));
    await tester.pump();
    expect(
        find.textContaining('Could not save this check-in.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Synthetic draft');
    await tester.ensureVisible(find.text('Save check-in'));
    await tester.tap(find.text('Save check-in'));
    await tester.pump();
    expect(attempts, 2);
  });
  testWidgets('background clears unsaved optional fields without saving',
      (tester) async {
    var saves = 0;
    await pump(tester, MoodCheckInScreen(save: (_) async {
      saves++;
    }));
    await tester.enterText(find.byType(TextField), 'Synthetic draft');
    await tester.tap(find.text('Include energy (optional)'));
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.byKey(const ValueKey('energy-slider')), findsNothing);
    expect(saves, 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets('history presents factual sample counts and missing measurements',
      (tester) async {
    await pump(tester,
        MoodHistoryScreen(load: () async => [entry(mood: 4)], now: () => now));
    await tester.pumpAndSettle();
    expect(find.text('1 mood check-ins'), findsOneWidget);
    expect(find.text('Average recorded mood: 4.0/10'), findsOneWidget);
    expect(find.text('Energy: not recorded'), findsOneWidget);
    expect(find.text('Sleep: not recorded'), findsOneWidget);
  });
  testWidgets('history handles late completion after disposal', (tester) async {
    final pending = Completer<List<MoodEntry>>();
    await pump(tester, MoodHistoryScreen(load: () => pending.future));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete([entry()]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('history failure is not misreported as empty history',
      (tester) async {
    await pump(
        tester,
        MoodHistoryScreen(
            load: () async => throw StateError('synthetic failure')));
    await tester.pumpAndSettle();
    expect(find.textContaining('History could not be opened.'), findsOneWidget);
    expect(find.text('No check-ins yet.'), findsNothing);
  });
}
