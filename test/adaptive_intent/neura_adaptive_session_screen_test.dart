import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_controller.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_intent_runtime.dart';
import 'package:neuro_companion/adaptive_intent/neura_adaptive_session_screen.dart';

void main() {
  testWidgets('session screen tracks local progress and emits an outcome', (
    tester,
  ) async {
    final controller = NeuraAdaptiveIntentController();
    final runtime = NeuraAdaptiveIntentRuntime(
      controller: controller,
      clock: () => DateTime.utc(2026, 8, 23, 12),
    );
    addTearDown(runtime.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NeuraAdaptiveSessionScreen(runtime: runtime)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('adaptive-session-start')));
    await tester.pumpAndSettle();
    expect(find.text('Active local plan'), findsOneWidget);

    await _tapKey(tester, 'adaptive-session-complete-organize-gather');
    await _tapKey(tester, 'adaptive-session-defer-organize-groups');
    await _tapKey(tester, 'adaptive-session-defer-organize-next');
    await _tapKey(tester, 'adaptive-session-finish');

    expect(runtime.session, isNull);
    expect(runtime.lastOutcome, isNotNull);
    expect(find.text('Outcome receipt'), findsOneWidget);
    expect(
      runtime.lastOutcome!.toJson().toString(),
      isNot(contains('Organize my next three priorities')),
    );
  });

  testWidgets('Safe Mode disables session creation', (tester) async {
    final controller = NeuraAdaptiveIntentController(safeMode: true);
    final runtime = NeuraAdaptiveIntentRuntime(controller: controller);
    addTearDown(runtime.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NeuraAdaptiveSessionScreen(runtime: runtime)),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('adaptive-session-start')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Safe Mode is active'), findsOneWidget);
  });
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
