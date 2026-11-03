import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_animated_body.dart';
import 'package:neuro_companion/mascot/mascot_window_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

// Synthetic window messages only: no native windows, speech or capture.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const bootstrap = MethodChannel('window_manager_plus');
  const window = MethodChannel('window_manager_plus_1');

  Future<void> event(String kind, [Map<String, Object> data = const {}]) async {
    await WindowManagerPlus.current.listeners.single.onEventFromWindow(
      'neura_state',
      0,
      {'v': 1, 'kind': kind, ...data},
    );
  }

  NeuraAnimatedBody body(WidgetTester tester) =>
      tester.widget<NeuraAnimatedBody>(find.byType(NeuraAnimatedBody));

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({
      'neura.mascot.window.x': 10.0,
      'neura.mascot.window.y': 10.0,
    });
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(bootstrap, (_) async => null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window,
        (call) async {
      if (call.method.startsWith('is')) return false;
      return null;
    });
    await WindowManagerPlus.ensureInitialized(1);
  });
  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(bootstrap, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
  });

  testWidgets(
      'mascot requires bridge activity and ignores its own inactive focus',
      (tester) async {
    await tester.pumpWidget(const MascotWindowApp());
    await tester.pumpAndSettle();
    expect(body(tester).animate, isFalse);
    expect(body(tester).respectAppLifecycle, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await event('thinking', {'on': true});
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    await event('body', {'active': true, 'safe': false, 'motion': 'subtle'});
    await tester.pump();
    expect(body(tester).animate, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await event('body', {'active': false, 'safe': false, 'motion': 'subtle'});
    await tester.pumpAndSettle();
    expect(body(tester).animate, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await event('body', {'active': true, 'safe': false, 'motion': 'subtle'});
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(WindowManagerPlus.current.listeners, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'mascot Safe Mode, Still, malformed activity and reduced motion stop all visual tickers',
      (tester) async {
    await tester.pumpWidget(const MascotWindowApp());
    await tester.pumpAndSettle();
    for (final blocked in <Map<String, Object>>[
      {'active': true, 'safe': true, 'motion': 'expressive'},
      {'active': true, 'safe': false, 'motion': 'still'},
      {'safe': false, 'motion': 'expressive'},
      {'active': true, 'safe': false, 'motion': 'unknown'},
    ]) {
      await event(
          'body', {'active': true, 'safe': false, 'motion': 'expressive'});
      await event('talking', {'on': true});
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await event('body', blocked);
      await event('pulse', {'wave': true});
      await tester.pumpAndSettle();
      expect(body(tester).animate, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    }
    await event('body', {'active': true, 'safe': false, 'motion': 'subtle'});
    await event('thinking', {'on': true});
    await tester.pump();
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
