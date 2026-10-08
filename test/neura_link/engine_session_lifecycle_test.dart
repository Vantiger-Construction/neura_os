import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_link/engine_session.dart';
import 'package:neuro_companion/neura_link/neura_console_page.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_error_pipeline.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/engine_synthetic_session');
  late ValueNotifier<bool> safe;
  late ValueNotifier<NeuraFatalError?> recovery;
  late List<MethodCall> calls;

  EngineSession create({bool supported = true}) =>
      EngineSession(safeMode: safe, recovery: recovery, supported: supported);

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    safe = ValueNotifier(false);
    recovery = ValueNotifier(null);
    calls = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'startSynthetic' => 'starting',
        'syntheticStatus' => 'ready',
        'blockSynthetic' => 'blocked',
        _ => 'stopped',
      };
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    safe.dispose();
    recovery.dispose();
    debugDefaultTargetPlatformOverride = null;
    SafeBoot.instance.safeMode.value = false;
    NeuraErrorPipeline.instance.clearFatalError();
  });

  testWidgets('explicit start sends only argument-free synthetic operations', (
    tester,
  ) async {
    final session = create();
    expect(calls, isEmpty);
    await session.start();
    expect(session.state, EngineSessionState.starting);
    await tester.pump(const Duration(seconds: 1));
    expect(session.state, EngineSessionState.ready);
    expect(calls.map((call) => call.method), [
      'startSynthetic',
      'syntheticStatus',
    ]);
    expect(calls.every((call) => call.arguments == null), isTrue);
    await session.stop();
    expect(session.state, EngineSessionState.stopped);
    session.dispose();
    await tester.pump();
  });

  for (final state in AppLifecycleState.values.where(
    (state) => state != AppLifecycleState.resumed,
  )) {
    testWidgets('$state ends the session and resume never restarts it', (
      tester,
    ) async {
      final session = create();
      await session.start();
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(session.state, EngineSessionState.stopped);
      expect(session.canStart, isFalse);
      expect(calls.last.method, 'stopSynthetic');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(session.state, EngineSessionState.stopped);
      expect(
        calls.where((call) => call.method == 'startSynthetic'),
        hasLength(1),
      );
      await session.start();
      expect(
        calls.where((call) => call.method == 'startSynthetic'),
        hasLength(2),
      );
      session.dispose();
      await tester.pump();
    });
  }

  for (final reason in ['Safe Mode', 'recovery']) {
    testWidgets('$reason blocks startup and discards a late ready response', (
      tester,
    ) async {
      final lateReply = Completer<String>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'startSynthetic') return lateReply.future;
        return 'blocked';
      });
      final session = create();
      final starting = session.start();
      await tester.pump();
      if (reason == 'Safe Mode') {
        safe.value = true;
      } else {
        recovery.value = const NeuraFatalError(
          source: 'test',
          phase: 'runtime',
        );
      }
      await tester.pump();
      expect(session.state, EngineSessionState.blocked);
      expect(calls.last.method, 'blockSynthetic');
      lateReply.complete('ready');
      await starting;
      expect(session.state, EngineSessionState.blocked);
      safe.value = false;
      recovery.value = null;
      await session.start();
      expect(
        calls.where((call) => call.method == 'startSynthetic'),
        hasLength(1),
      );
      session.dispose();
      await tester.pump();
    });
  }

  testWidgets('screen disposal invalidates startup and sends stop', (
    tester,
  ) async {
    final lateReply = Completer<String>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'startSynthetic' ? lateReply.future : 'stopped';
    });
    final session = create();
    final starting = session.start();
    await tester.pump();
    session.dispose();
    await tester.pump();
    lateReply.complete('ready');
    await starting;
    expect(session.state, EngineSessionState.stopped);
    expect(calls.last.method, 'stopSynthetic');
    await tester.pump(const Duration(seconds: 2));
    expect(calls.where((call) => call.method == 'syntheticStatus'), isEmpty);
  });

  testWidgets(
    'late status from a stopped generation cannot overwrite restart',
    (tester) async {
      final lateReply = Completer<String>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'syntheticStatus') return lateReply.future;
        return call.method == 'startSynthetic' ? 'starting' : 'stopped';
      });
      final session = create();
      await session.start();
      await tester.pump(const Duration(seconds: 1));
      await session.stop();
      await session.start();
      lateReply.complete('ready');
      await tester.pump();
      expect(session.state, EngineSessionState.starting);
      session.dispose();
      await tester.pump();
    },
  );

  testWidgets('preexisting Safe Mode and recovery never admit a start', (
    tester,
  ) async {
    safe.value = true;
    recovery.value = const NeuraFatalError(source: 'test', phase: 'bootstrap');
    final session = create();
    await session.start();
    await tester.pump();
    expect(calls.where((call) => call.method == 'startSynthetic'), isEmpty);
    expect(session.state, EngineSessionState.blocked);
    session.dispose();
    await tester.pump();
  });

  testWidgets('unsupported platforms never launch or fall back', (
    tester,
  ) async {
    final session = create(supported: false);
    await session.start();
    expect(session.state, EngineSessionState.unavailable);
    session.dispose();
    await tester.pump();
    expect(calls, isEmpty);
  });

  for (final failure in ['label', 'exception']) {
    testWidgets(
      '$failure payload cannot leak credentials to state or diagnostics',
      (tester) async {
        const credential = 'synthetic-credential-must-not-be-rendered';
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'startSynthetic') {
            if (failure == 'exception') {
              throw PlatformException(
                code: 'test',
                message: credential,
                details: {'token': credential},
              );
            }
            return credential;
          }
          return 'stopped';
        });
        final session = create();
        await session.start();
        expect(session.state, EngineSessionState.error);
        expect(calls.last.method, 'stopSynthetic');
        expect(calls.every((call) => call.arguments == null), isTrue);
        expect(tester.takeException(), isNull);
        session.dispose();
        await tester.pump();
      },
    );
  }

  testWidgets(
    'Console is idle on open, has no personal input, and stops on removal',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(const MaterialApp(home: NeuraConsolePage()));
      expect(calls, isEmpty);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Start synthetic check'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(
          'Hello verified. Diagnostics verified. Echo adapter: degraded.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.last.method, 'stopSynthetic');
      expect(calls.every((call) => call.arguments == null), isTrue);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
