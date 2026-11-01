import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_room_presence_avatar.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';

Widget host({bool reduceMotion = false, bool ticker = true}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: TickerMode(
            enabled: ticker,
            child: const Center(
                child: SizedBox.square(
              dimension: 180,
              child: NeuraRoomPresenceAvatar(
                  room: NeuraRoom.penthouse,
                  phase: NeuraPresencePhase.thinking,
                  motion: NeuraCompanionMotion.subtle,
                  scale: NeuraCompanionScale.standard),
            ))),
      ),
    );

void main() {
  testWidgets('reduced motion and covered routes stop scheduling motion frames',
      (tester) async {
    await tester.pumpWidget(host(reduceMotion: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.hasScheduledFrame, true);
    await tester.pumpWidget(host(ticker: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background suspends avatar motion, foreground resumes it',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.hasScheduledFrame, true);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
