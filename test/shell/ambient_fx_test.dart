import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/src/shell/ambient_fx.dart';

Widget _host({required bool enabled}) => MaterialApp(
      home: Stack(children: [AmbientFx(enabled: enabled)]),
    );

void main() {
  testWidgets('animates while enabled', (tester) async {
    await tester.pumpWidget(_host(enabled: true));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('never starts its controller while disabled', (tester) async {
    await tester.pumpWidget(_host(enabled: false));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('stops animating when toggled off and resumes when toggled on',
      (tester) async {
    await tester.pumpWidget(_host(enabled: true));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(_host(enabled: false));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_host(enabled: true));
    expect(tester.hasRunningAnimations, isTrue);
  });
}
