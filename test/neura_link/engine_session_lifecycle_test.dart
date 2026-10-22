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
        'startSynthetic' || 'resumeSynthetic' => 'starting',
        'pauseSynthetic' => 'paused',
        'syntheticStatus' => 'idle',
        'blockSynthetic' => 'blocked',
        _ => 'disabled',
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
    expect(session.state, EngineSessionState.idle);
    expect(calls.map((call) => call.method), [
      'startSynthetic',
      'syntheticStatus',
    ]);
    expect(calls.every((call) => call.arguments == null), isTrue);
    await session.stop();
    expect(session.state, EngineSessionState.disabled);
    session.dispose();
    await tester.pump();
  });

  testWidgets('working and idle are distinct and pause needs explicit resume', (
    tester,
  ) async {
    var status = 'working';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'startSynthetic' || 'resumeSynthetic' => 'starting',
        'pauseSynthetic' => 'paused',
        'syntheticStatus' => status,
        _ => 'disabled',
      };
    });
    final session = create();
    expect(session.state, EngineSessionState.disabled);
    await session.start();
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.state, EngineSessionState.working);
    expect(session.canPause, isTrue);
    expect(session.canStart, isFalse);
    status = 'idle';
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.state, EngineSessionState.idle);
    await session.pause();
    expect(session.state, EngineSessionState.paused);
    expect(session.canResume, isTrue);
    expect(session.canStart, isFalse);
    status = 'paused';
    await tester.pump(const Duration(seconds: 2));
    expect(calls.where((call) => call.method == 'resumeSynthetic'), isEmpty);
    await session.start();
    expect(
      calls.where((call) => call.method == 'startSynthetic'),
      hasLength(1),
    );
    await session.resume();
    expect(session.state, EngineSessionState.starting);
    expect(calls.last.method, 'resumeSynthetic');
    expect(calls.every((call) => call.arguments == null), isTrue);
    session.dispose();
    await tester.pump();
  });

  testWidgets(
      'safety change during notification prevents stale start or resume', (
    tester,
  ) async {
    for (final operation in ['start', 'resume']) {
      safe.value = false;
      final session = create();
      if (operation == 'resume') {
        await session.start();
        await session.pause();
      }
      calls.clear();
      session.addListener(() {
        if (session.state == EngineSessionState.starting) safe.value = true;
      });
      if (operation == 'start') {
        await session.start();
      } else {
        await session.resume();
      }
      await tester.pump();
      expect(session.state, EngineSessionState.blocked);
      expect(calls.map((call) => call.method), ['blockSynthetic']);
      session.dispose();
      await tester.pump();
    }
  });

  testWidgets('pause invalidates pending startup and status replies', (
    tester,
  ) async {
    for (final pending in ['startSynthetic', 'syntheticStatus']) {
      final lateReply = Completer<String>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == pending) return lateReply.future;
        return switch (call.method) {
          'pauseSynthetic' => 'paused',
          'startSynthetic' || 'resumeSynthetic' => 'starting',
          _ => 'disabled',
        };
      });
      final session = create();
      final starting = session.start();
      await tester.pump();
      if (pending == 'syntheticStatus') {
        await starting;
        await tester.pump(const Duration(milliseconds: 100));
      }
      await session.pause();
      expect(session.state, EngineSessionState.paused);
      await session.resume();
      lateReply.complete('idle');
      await starting;
      await tester.pump();
      expect(session.state, EngineSessionState.starting);
      session.dispose();
      await tester.pump();
    }
  });

  testWidgets('late pause cannot overwrite a stop and replacement session', (
    tester,
  ) async {
    final lateReply = Completer<String>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'pauseSynthetic') return lateReply.future;
      return call.method == 'startSynthetic' ? 'starting' : 'disabled';
    });
    final session = create();
    await session.start();
    final pausing = session.pause();
    await tester.pump();
    expect(session.canResume, isFalse);
    await session.resume();
    expect(calls.where((call) => call.method == 'resumeSynthetic'), isEmpty);
    await session.stop();
    await session.start();
    lateReply.complete('paused');
    await pausing;
    expect(session.state, EngineSessionState.starting);
    session.dispose();
    await tester.pump();
  });

  testWidgets(
    'resource pause has no automatic retry and foreground loss disables resume',
    (tester) async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'startSynthetic' ? 'starting' : 'paused';
      });
      final session = create();
      await session.start();
      await tester.pump(const Duration(milliseconds: 100));
      expect(session.state, EngineSessionState.paused);
      expect(session.canResume, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(calls.where((call) => call.method == 'resumeSynthetic'), isEmpty);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(session.state, EngineSessionState.disabled);
      expect(session.canResume, isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await session.resume();
      expect(session.state, EngineSessionState.disabled);
      expect(calls.where((call) => call.method == 'resumeSynthetic'), isEmpty);
      session.dispose();
      await tester.pump();
    },
  );

  for (final reason in ['Safe Mode', 'recovery']) {
    testWidgets('$reason blocks paused work and rejects a late resume', (
      tester,
    ) async {
      final lateReply = Completer<String>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return switch (call.method) {
          'startSynthetic' => 'working',
          'pauseSynthetic' => 'paused',
          'resumeSynthetic' => lateReply.future,
          _ => 'blocked',
        };
      });
      final session = create();
      await session.start();
      await session.pause();
      final resuming = session.resume();
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
      expect(calls.last.method, 'blockSynthetic');
      lateReply.complete('idle');
      await resuming;
      expect(session.state, EngineSessionState.blocked);
      expect(session.canResume, isFalse);
      safe.value = false;
      recovery.value = null;
      await session.resume();
      await session.start();
      expect(
        calls.where((call) => call.method == 'resumeSynthetic'),
        hasLength(1),
      );
      session.dispose();
      await tester.pump();
    });
  }

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
      expect(session.state, EngineSessionState.disabled);
      expect(session.canStart, isFalse);
      expect(calls.last.method, 'stopSynthetic');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(session.state, EngineSessionState.disabled);
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
    testWidgets('$reason blocks startup and discards a late idle response', (
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
      lateReply.complete('idle');
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
      return call.method == 'startSynthetic' ? lateReply.future : 'disabled';
    });
    final session = create();
    final starting = session.start();
    await tester.pump();
    session.dispose();
    await tester.pump();
    lateReply.complete('idle');
    await starting;
    expect(session.state, EngineSessionState.disabled);
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
        return call.method == 'startSynthetic' ? 'starting' : 'disabled';
      });
      final session = create();
      await session.start();
      await tester.pump(const Duration(seconds: 1));
      await session.stop();
      await session.start();
      lateReply.complete('idle');
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
          return 'disabled';
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
    'Console is disabled on open, has no personal input, and stops on removal',
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
          'Idle. Hello and diagnostics verified. Echo adapter: degraded.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(calls.last.method, 'pauseSynthetic');
      expect(
        find.text(
            'Paused. Pending work was discarded. Resume starts a fresh check.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(calls.last.method, 'resumeSynthetic');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.last.method, 'stopSynthetic');
      expect(calls.every((call) => call.arguments == null), isTrue);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('local check needs acknowledgement and sends no arguments', (
    tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'startLocalCheck' => 'starting',
        'syntheticStatus' => 'idle',
        _ => 'disabled',
      };
    });
    final session = create();
    expect(session.canStartLocal, isFalse);
    await session.startLocal();
    expect(calls, isEmpty);
    session.acknowledgeLocalModel(true);
    expect(session.canStartLocal, isTrue);
    await session.startLocal();
    expect(session.mode, EngineCheckMode.local);
    await tester.pump(const Duration(seconds: 1));
    expect(session.state, EngineSessionState.idle);
    expect(calls.map((call) => call.method), [
      'startLocalCheck',
      'syntheticStatus',
    ]);
    expect(calls.every((call) => call.arguments == null), isTrue);
    await session.stop();
    await session.start();
    expect(session.mode, EngineCheckMode.echo);
    session.dispose();
    await tester.pump();
  });

  testWidgets('model unavailable stops the session and allows a new start', (
    tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'startLocalCheck' => 'starting',
        'syntheticStatus' => 'model_unavailable',
        _ => 'disabled',
      };
    });
    final session = create();
    session.acknowledgeLocalModel(true);
    await session.startLocal();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(session.state, EngineSessionState.modelUnavailable);
    expect(calls.last.method, 'stopSynthetic');
    expect(session.canStart, isTrue);
    expect(session.canStartLocal, isTrue);
    session.dispose();
    await tester.pump();
  });

  testWidgets('Safe Mode clears the local model acknowledgement', (
    tester,
  ) async {
    final session = create();
    session.acknowledgeLocalModel(true);
    safe.value = true;
    await tester.pump();
    expect(session.localAcknowledged, isFalse);
    session.acknowledgeLocalModel(true);
    expect(session.localAcknowledged, isFalse);
    await session.startLocal();
    expect(calls.where((call) => call.method == 'startLocalCheck'), isEmpty);
    session.dispose();
    await tester.pump();
  });

  testWidgets('Console local check needs the acknowledgement checkbox', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'startLocalCheck' => 'starting',
        'syntheticStatus' => 'idle',
        _ => 'disabled',
      };
    });
    await tester.pumpWidget(const MaterialApp(home: NeuraConsolePage()));
    final start = find.text('Start local model check');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    expect(calls, isEmpty);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls.map((call) => call.method), [
      'startLocalCheck',
      'syntheticStatus',
    ]);
    expect(
      find.text(
        'Idle. Your local model answered the fixed hello. '
        'Nothing was kept or sent anywhere.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(calls.last.method, 'stopSynthetic');
    expect(calls.every((call) => call.arguments == null), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
