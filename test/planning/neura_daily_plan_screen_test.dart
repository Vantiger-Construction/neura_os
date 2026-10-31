import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/planning/neura_daily_plan_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

void main() {
  testWidgets(
      'user previews, approves and records progress; edits revoke approval',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NeuraDailyPlanScreen()));
    await tester.enterText(find.byType(TextField).first, 'Tidy my desk');
    await tester.enterText(
        find.byType(TextField).last, 'Clear one corner\nTake a break');
    await tester.ensureVisible(find.text('Preview my plan'));
    await tester.tap(find.text('Preview my plan'));
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNull);
    await tester.scrollUntilVisible(find.text('Use this plan'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Use this plan'));
    await tester.pump();
    await tester.ensureVisible(find.text('Clear one corner'));
    await tester.tap(find.text('Clear one corner'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('1 of 2 steps complete'), -100,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('1 of 2 steps complete'), findsOneWidget);
    await tester.ensureVisible(find.text('This feels too big'));
    await tester.tap(find.text('This feels too big'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Stand up for one minute');
    await tester.tap(find.text('Preview smaller step'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 steps complete'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Use this plan'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Stand up for one minute'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).last)
            .onChanged,
        isNull);
    await tester.scrollUntilVisible(find.text('My goal'), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField).first, 'New goal');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background and Safe Mode clear both editor and plan',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NeuraDailyPlanScreen()));
    await tester.enterText(find.byType(TextField).first, 'Private goal');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Private goal'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.enterText(
        find.byType(TextField).first, 'Another private goal');
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    expect(find.text('Another private goal'), findsNothing);
    SafeBoot.instance.safeMode.value = false;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
