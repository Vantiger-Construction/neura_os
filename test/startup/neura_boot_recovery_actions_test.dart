import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/startup/neura_boot_recovery_actions.dart';

void main() {
  testWidgets(
      'recovery actions are explicit and export only allowlisted summary',
      (tester) async {
    var retry = 0;
    var safe = 0;
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NeuraBootRecoveryActions(
      onRetry: () => retry++,
      onSafeMode: () => safe++,
      safeMode: false,
      module: '/secret/token',
    ))));
    expect(retry, 0);
    expect(safe, 0);
    await tester.tap(find.text('Retry startup'));
    await tester.tap(find.text('Retry in Safe Mode'));
    expect(retry, 1);
    expect(safe, 1);
    await tester.tap(find.text('Preview startup summary'));
    await tester.pumpAndSettle();
    expect(copied, isNull);
    await tester.tap(find.text('Copy summary'));
    await tester.pumpAndSettle();
    expect(copied, contains('module: unknown'));
    expect(copied, isNot(contains('/secret/token')));
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'busy recovery disables retries; Safe Mode cannot be switched off',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NeuraBootRecoveryActions(
      onRetry: () => fail('busy'),
      onSafeMode: () => fail('busy'),
      safeMode: true,
      module: 'PrefsCache',
      busy: true,
    ))));
    expect(find.text('Retry in Safe Mode'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
}
