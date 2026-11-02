import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_offline_budget.dart';
import 'package:neuro_companion/widgets/neura_offline_controls.dart';

void main() {
  const channel = MethodChannel('neura/engine_synthetic_session');

  testWidgets('no automatic probe; a backgrounded RAM result is discarded',
      (tester) async {
    var calls = 0;
    final pending = Completer<Map<String, int>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) {
      calls++;
      expect(call.method, 'readOfflineMemory');
      return pending.future;
    });
    await tester.pumpWidget(const MaterialApp(
        home: NeuraOfflineControls(budget: NeuraOfflineBudget.compact)));
    expect(calls, 0);
    await tester.tap(find.text('Check available RAM'));
    await tester.pump();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    pending.complete({'totalMiB': 8192, 'availableMiB': 4096});
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.textContaining('4096 MiB'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
