import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_companion/modules/camera_hawk/camera_hawk_client.dart';
import 'package:neuro_companion/modules/camera_hawk/camera_hawk_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

void main() {
  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });
  tearDown(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });

  void windowsTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      // The viewer requires a foreground session, including in the test binding.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        // Restore before testWidgets checks its foundation invariants.
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });
  }

  for (final boundary in ['safe-mode', 'recovery', 'background', 'closure']) {
    windowsTest('$boundary clears and revokes the viewer session',
        (tester) async {
      var logouts = 0;
      final client = CameraHawkClient(transport: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return http.Response('{"access_token":"secret"}', 200);
        }
        if (r.url.path.endsWith('/logout')) {
          logouts++;
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('[{"name":"Door","enabled":true}]', 200);
      }));
      await tester
          .pumpWidget(MaterialApp(home: CameraHawkScreen(client: client)));
      expect(client.connected, isFalse);
      await tester.enterText(find.byType(TextField).at(0), 'viewer');
      await tester.enterText(find.byType(TextField).at(1), 'password');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Door'), findsOneWidget);
      expect(client.connected, isTrue);
      switch (boundary) {
        case 'safe-mode':
          SafeBoot.instance.safeMode.value = true;
          break;
        case 'recovery':
          SafeBoot.instance.restartRequired.value = true;
          break;
        case 'background':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          break;
        case 'closure':
          await tester.pumpWidget(const SizedBox.shrink());
          break;
      }
      await tester.pumpAndSettle();
      expect(client.connected, isFalse);
      expect(logouts, 1);
      expect(find.text('Door'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }

  windowsTest('Safe Mode blocks sign-in and dashboard handoff', (tester) async {
    SafeBoot.instance.safeMode.value = true;
    var calls = 0;
    final client = CameraHawkClient(transport: MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));
    await tester
        .pumpWidget(MaterialApp(home: CameraHawkScreen(client: client)));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
