import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/src/modules/focus/focus_controller.dart';
import 'package:neuro_companion/src/modules/focus/focus_mode.dart';
import 'package:neuro_companion/src/shell/neura_shell.dart';

void main() {
  for (final mode in FocusMode.values.where((mode) => mode != FocusMode.off)) {
    testWidgets('$mode banner renders outside the navigator Material',
        (tester) async {
      final previous = FocusController.instance.state.value;
      addTearDown(() => FocusController.instance.state.value = previous);
      FocusController.instance.state.value =
          FocusState(mode: mode, startedAt: DateTime(2026));

      await tester.pumpWidget(MaterialApp(
        builder: (_, child) => NeuraAmbientShell(child: child!),
        home: const Scaffold(body: Text('Page content')),
      ));
      await tester.pump();

      expect(find.text('${mode.label} Mode'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
