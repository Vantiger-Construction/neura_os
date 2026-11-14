import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_shell/neura_shell.dart';
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool previousSafeMode;

  setUp(() {
    previousSafeMode = SafeBoot.instance.safeMode.value;
    SafeBoot.instance.safeMode.value = true;
  });
  tearDown(() {
    SafeBoot.instance.safeMode.value = previousSafeMode;
  });

  testWidgets('docking during mount notifies the shell after build',
      (tester) async {
    final shell = NeuraShellState();
    var notifications = 0;
    shell.addListener(() => notifications++);
    await tester.pumpWidget(
      NeuraShellScope(
        notifier: shell,
        child: Builder(builder: (context) {
          final state = NeuraShell.of(context);
          unawaited(state.setAvatarDockedInApp(true));
          expect(state.avatarDockedInApp, isTrue);
          return const SizedBox.shrink();
        }),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(notifications, 1);
    await tester.pump();
    expect(notifications, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
  });

  testWidgets('disposed shell ignores a deferred docking notification',
      (tester) async {
    final shell = NeuraShellState();
    var notifications = 0;
    shell.addListener(() => notifications++);
    await tester.pumpWidget(Builder(builder: (_) {
      unawaited(shell.setAvatarDockedInApp(true));
      shell.dispose();
      return const SizedBox.shrink();
    }));
    expect(tester.takeException(), isNull);
    expect(notifications, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
