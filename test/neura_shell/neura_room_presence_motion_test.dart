import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_room_presence_avatar.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';

Widget host({
  bool reduceMotion = false,
  bool ticker = true,
  NeuraRoom room = NeuraRoom.penthouse,
  NeuraPresencePhase phase = NeuraPresencePhase.thinking,
  NeuraCompanionMotion motion = NeuraCompanionMotion.subtle,
  GlobalKey<NavigatorState>? navigatorKey,
}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: TickerMode(
          enabled: ticker,
          child: Center(
            child: SizedBox.square(
              dimension: 180,
              child: NeuraRoomPresenceAvatar(
                room: room,
                phase: phase,
                motion: motion,
                scale: NeuraCompanionScale.standard,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool previousSafe;
  late bool previousRecovery;
  late ShellPrefs previousPrefs;
  setUp(() {
    previousSafe = SafeBoot.instance.safeMode.value;
    previousRecovery = SafeBoot.instance.restartRequired.value;
    previousPrefs = ShellPrefsController.instance.prefs.value;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    NeuraMotion.instance.start();
  });
  tearDown(() {
    NeuraMotion.instance.stop();
    SafeBoot.instance.safeMode.value = previousSafe;
    SafeBoot.instance.restartRequired.value = previousRecovery;
    ShellPrefsController.instance.prefs.value = previousPrefs;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'reduced motion and covered routes stop scheduling motion frames',
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
    },
  );

  testWidgets('background suspends avatar motion, foreground resumes it', (
    tester,
  ) async {
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

  testWidgets('a real covering route suspends motion and pop restores it', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(host(navigatorKey: navigator));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room transitions honor Still, Safe Mode and reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));
    for (final blocked in [
      host(room: NeuraRoom.reflectionBay, motion: NeuraCompanionMotion.still),
      host(room: NeuraRoom.penthouse, phase: NeuraPresencePhase.safeMode),
      host(room: NeuraRoom.reflectionBay, reduceMotion: true),
    ]) {
      await tester.pumpWidget(blocked);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(host(room: NeuraRoom.reflectionBay));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
