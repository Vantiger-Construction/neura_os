import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/widgets/neura_activity_badge.dart';

void main() {
  testWidgets('activity is accurate for offline, background and safety states',
      (tester) async {
    final state =
        ValueNotifier(const NeuraPresenceSnapshot(NeuraPresencePhase.idle));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NeuraActivityBadge(offline: true, state: state))));
    expect(find.text('Ready offline'), findsOneWidget);
    state.value = const NeuraPresenceSnapshot(NeuraPresencePhase.thinking);
    await tester.pump();
    expect(find.text('Thinking offline'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Paused · app in background'), findsOneWidget);
    state.value = const NeuraPresenceSnapshot(NeuraPresencePhase.safeMode);
    await tester.pump();
    expect(find.text('Safe Mode · audio is off'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    state.value = const NeuraPresenceSnapshot(NeuraPresencePhase.listening);
    await tester.pump();
    expect(find.text('Listening on this device'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
