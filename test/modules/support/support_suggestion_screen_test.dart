import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/support/guided_support_activity.dart';
import 'package:neuro_companion/modules/support/guided_support_screen.dart';
import 'package:neuro_companion/modules/support/support_suggestion_choices.dart';
import 'package:neuro_companion/modules/support/support_suggestion_screen.dart';
import 'package:neuro_companion/preview/neura_demo_session.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });
  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });
  testWidgets(
      'request-only waits for the explicit request before offering an activity',
      (tester) async {
    final store = DemoSupportStore();
    await store.rememberAfterConfirmation(GuidedSupportActivity.grounding,
        stillApproved: () => true);
    await store.saveChoicesAfterConfirmation(
        SupportSuggestionChoices(onlyWhenAsked: true),
        stillApproved: () => true);
    await tester
        .pumpWidget(MaterialApp(home: GuidedSupportScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Try grounding pause again'), findsNothing);
    await tap(tester, 'Show suggested activity');
    expect(find.text('Try grounding pause again'), findsOneWidget);
  });
  testWidgets(
      'excluded activities stay manually available but are not suggested',
      (tester) async {
    final store = DemoSupportStore();
    await store.rememberAfterConfirmation(GuidedSupportActivity.gentleBreathing,
        stillApproved: () => true);
    await store.saveChoicesAfterConfirmation(
        SupportSuggestionChoices(
            excluded: {GuidedSupportActivity.gentleBreathing}),
        stillApproved: () => true);
    await tester
        .pumpWidget(MaterialApp(home: GuidedSupportScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Try gentle breathing again'), findsNothing);
    expect(find.text('Gentle breathing'), findsOneWidget);
  });
  testWidgets('choice edits are not saved until specifically approved',
      (tester) async {
    final store = DemoSupportStore();
    await tester
        .pumpWidget(MaterialApp(home: SupportSuggestionScreen(store: store)));
    await tap(tester, 'Open my suggestion choices');
    await tap(tester, 'Only suggest when I ask');
    expect((await store.readChoices()).onlyWhenAsked, isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save suggestion choices'))
            .onPressed,
        isNull);
    await tap(tester, 'Save these choices on this device');
    await tap(tester, 'Save suggestion choices');
    expect((await store.readChoices()).onlyWhenAsked, isTrue);
    await tap(tester, 'Forget suggestion choices');
    expect((await store.readChoices()).onlyWhenAsked, isFalse);
  });
  testWidgets('background hides choices and invalidates old approval callbacks',
      (tester) async {
    final store = DemoSupportStore();
    await tester
        .pumpWidget(MaterialApp(home: SupportSuggestionScreen(store: store)));
    await tap(tester, 'Open my suggestion choices');
    final approval = tester
        .widget<CheckboxListTile>(find.widgetWithText(
            CheckboxListTile, 'Save these choices on this device'))
        .onChanged!;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(SwitchListTile), findsNothing);
    await tap(tester, 'Open my suggestion choices');
    approval(true);
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(find.widgetWithText(
                CheckboxListTile, 'Save these choices on this device'))
            .value,
        isFalse);
  });
}
