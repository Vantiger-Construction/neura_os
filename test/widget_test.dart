import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Basic smoke test — verify the framework can pump a minimal widget.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Neura OS'))),
      ),
    );

    expect(find.text('Neura OS'), findsOneWidget);
  });
}
