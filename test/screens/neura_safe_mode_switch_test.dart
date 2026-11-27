import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/modules/settings/settings.dart';
import 'package:neuro_companion/widgets/neura_safe_mode_switch.dart';

void main() {
  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });
  tearDown(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });

  testWidgets(
      'Settings exposes Safe Mode and explains the restart when cleared',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    final finder = find.byKey(const Key('safe-mode-switch'));
    expect(tester.widget<SwitchListTile>(finder).value, isFalse);

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(SafeBoot.instance.safeMode.value, isTrue);
    expect(tester.widget<SwitchListTile>(finder).value, isTrue);

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(SafeBoot.instance.safeMode.value, isTrue,
        reason: 'Turning the switch off must not revive native services.');
    expect(SafeBoot.instance.restartRequired.value, isTrue);
    expect(tester.widget<SwitchListTile>(finder).value, isFalse);
    expect(tester.widget<SwitchListTile>(finder).onChanged, isNull);
    expect(find.textContaining('Restart Neura to finish turning Safe Mode off'),
        findsOneWidget);
  });

  testWidgets('the switch reflects recovery changes while its page is open',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: NeuraSafeModeSwitch()),
    ));
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('safe-mode-switch')))
            .value,
        isTrue);
    expect(
        find.textContaining('Microphone, speech and cloud services are paused'),
        findsOneWidget);
  });
}
