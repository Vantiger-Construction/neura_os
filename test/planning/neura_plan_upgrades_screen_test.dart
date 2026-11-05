import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/planning/neura_daily_plan_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 150,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  await reveal(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  Future<void> mount(WidgetTester tester) async {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const MaterialApp(home: NeuraDailyPlanScreen()));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      SafeBoot.instance.safeMode.value = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }

  testWidgets(
      'template creates a draft and protects an existing plan from accidental replacement',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).first, 'My existing goal');
    await tap(tester, 'Choose a plan template');
    await tester.tap(find.text('Focus session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep my plan'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'My existing goal');
    await tap(tester, 'Choose a plan template');
    await tester.tap(find.text('Focus session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use template'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tap(tester, 'Preview my plan');
    await reveal(
        tester,
        find.widgetWithText(
            CheckboxListTile, 'Name the result I want from this session'));
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNull);
  });

  testWidgets(
      'focus view advances through unfinished steps without completing work automatically',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).first, 'Synthetic goal');
    await tester.enterText(
        find.byType(TextField).last, 'First step\nSecond step');
    await tap(tester, 'Preview my plan');
    await tap(tester, 'Use this plan');
    await tap(tester, 'Focus on next step');
    await reveal(tester, find.widgetWithText(CheckboxListTile, 'First step'));
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false);
    await tester.tap(find.text('First step'));
    await tester.pumpAndSettle();
    expect(find.text('First step'), findsNothing);
    expect(find.text('Second step'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'step edit, undo, and background clearing preserve approval boundaries',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).first, 'Synthetic goal');
    await tester.enterText(
        find.byType(TextField).last, 'First step\nSecond step');
    await tap(tester, 'Preview my plan');
    await tap(tester, 'Use this plan');
    await reveal(tester, find.byTooltip('Options for step 1'));
    await tester.tap(find.byTooltip('Options for step 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit step'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Updated step');
    await tester.tap(find.text('Preview change'));
    await tester.pumpAndSettle();
    await tap(tester, 'Undo last edit');
    await reveal(tester, find.text('First step'));
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('First step'), findsNothing);
    expect(find.text('Undo last edit'), findsNothing);
  });
}
