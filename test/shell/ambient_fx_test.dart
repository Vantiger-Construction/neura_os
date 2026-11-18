import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_room_backdrop.dart';
import 'package:neuro_companion/src/shell/ambient_fx.dart';

Widget _host({required bool enabled}) => MaterialApp(
      home: Stack(children: [AmbientFx(enabled: enabled)]),
    );

Finder _ambientPaint() => find.descendant(
      of: find.byType(AmbientFx),
      matching: find.byType(CustomPaint),
    );

void main() {
  // These layers sit under the Navigator and every route paints an opaque
  // background over them, so they must never keep the engine repainting.
  testWidgets('paints once while enabled without a running animation',
      (tester) async {
    await tester.pumpWidget(_host(enabled: true));
    expect(_ambientPaint(), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('paints nothing while disabled', (tester) async {
    await tester.pumpWidget(_host(enabled: false));
    expect(_ambientPaint(), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('toggling shows and hides the layer without animating',
      (tester) async {
    await tester.pumpWidget(_host(enabled: true));
    expect(_ambientPaint(), findsOneWidget);

    await tester.pumpWidget(_host(enabled: false));
    expect(_ambientPaint(), findsNothing);

    await tester.pumpWidget(_host(enabled: true));
    expect(_ambientPaint(), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('room backdrop settles after a room change and stays idle',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NeuraRoomBackdrop(room: NeuraRoom.penthouse)),
    );
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(
      const MaterialApp(home: NeuraRoomBackdrop(room: NeuraRoom.dreamAtrium)),
    );
    expect(tester.hasRunningAnimations, isTrue,
        reason: 'The room gradient eases to the new room.');
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
