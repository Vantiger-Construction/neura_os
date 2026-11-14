import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/mascot/mascot_window_app.dart';
import 'package:neuro_companion/mascot/mascot_window_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

// All windows, preferences and platform channels are synthetic. No app data,
// primary app services, hardware, audio or native windows are used here.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const bootstrap = MethodChannel('window_manager_plus');
  const window = MethodChannel('window_manager_plus_1');
  late List<Object> errors;
  late List<MethodCall> windowCalls;

  setUp(() {
    errors = [];
    windowCalls = [];
    SharedPreferences.setMockInitialValues({
      'neura.mascot.window.x': 10.0,
      'neura.mascot.window.y': 10.0,
    });
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(bootstrap, (_) async => null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window,
        (call) async {
      windowCalls.add(call);
      return call.method.startsWith('is') ? false : null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(bootstrap, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
  });

  Widget root(Future<void> Function(int) initialize) => MascotWindowBootstrap(
        windowId: 1,
        initializeWindow: initialize,
        onInitializationError: (error, _) => errors.add(error),
      );

  testWidgets('mounts the mascot only after initialization succeeds',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(root((id) async {
      expect(id, 1);
      await ready.future;
      await WindowManagerPlus.ensureInitialized(id);
    }));
    expect(find.byType(MascotWindowApp), findsNothing);
    expect(windowCalls, isEmpty);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MascotWindowApp), findsOneWidget);
    expect(errors, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(WindowManagerPlus.current.listeners, isEmpty);
  });

  testWidgets('missing plugin leaves a usable plugin-free secondary root',
      (tester) async {
    await tester.pumpWidget(root((_) async {
      throw MissingPluginException('Synthetic absent bootstrap channel');
    }));
    await tester.pumpAndSettle();
    expect(find.byType(MascotWindowApp), findsNothing);
    expect(find.textContaining('main Neura window'), findsOneWidget);
    expect(errors.single, isA<MissingPluginException>());
    expect(windowCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeout remains unavailable after late initialization',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(root((_) => ready.future));
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('main Neura window'), findsOneWidget);
    expect(errors.single, isA<TimeoutException>());
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MascotWindowApp), findsNothing);
    expect(errors, hasLength(1));
    expect(windowCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal suppresses late completion and error reporting',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(root((_) => ready.future));
    await tester.pumpWidget(const SizedBox());
    ready.completeError(StateError('Synthetic late initialization failure'));
    await tester.pumpAndSettle();
    expect(errors, isEmpty);
    expect(windowCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
