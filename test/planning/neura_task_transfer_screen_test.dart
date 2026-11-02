import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/planning/neura_task_transfer.dart';
import 'package:neuro_companion/planning/neura_task_transfer_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

void main() {
  testWidgets('import preview is explicit and clears on background',
      (tester) async {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final packet = await tester.runAsync(() => NeuraTaskTransfer.seal(
        NeuraTaskSnapshot(
            goal: 'Synthetic goal',
            steps: ['First step', 'Second step'],
            completed: {0})));
    await tester.pumpWidget(const MaterialApp(home: NeuraTaskTransferScreen()));
    await tester.enterText(find.byType(TextField).first, packet!.packet);
    await tester.enterText(find.byType(TextField).last, packet.key);
    final packetController =
        tester.widget<TextField>(find.byType(TextField).first).controller!;
    final keyController =
        tester.widget<TextField>(find.byType(TextField).last).controller!;
    await tester.ensureVisible(find.text('Decrypt and preview'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Decrypt and preview'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Synthetic goal'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Synthetic goal'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Bring this preview into my planner'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Bring this preview into my planner'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Synthetic goal'), findsNothing);
    expect(packetController.text, isEmpty);
    expect(keyController.text, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('safe mode clears an export preview and cannot recreate it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: NeuraTaskTransferScreen(
            snapshot: NeuraTaskSnapshot(
                goal: 'Private goal',
                steps: ['Private step'],
                completed: {}))));
    expect(find.text('Private goal'), findsOneWidget);
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    expect(find.text('Private goal'), findsNothing);
    expect(find.text('Create encrypted task packet'), findsNothing);
    SafeBoot.instance.safeMode.value = false;
    await tester.pump();
    expect(find.text('Private goal'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
