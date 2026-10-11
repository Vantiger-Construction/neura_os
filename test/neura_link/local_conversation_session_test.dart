import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_link/local_conversation_session.dart';
import 'package:neuro_companion/startup/neura_error_pipeline.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/local_conversation');
  late ValueNotifier<bool> safe;
  late ValueNotifier<NeuraFatalError?> recovery;
  late List<MethodCall> calls;
  late Map<String, Object> snapshot;
  late List<LocalConversationSession> sessions;

  LocalConversationSession create({bool supported = true}) {
    final session = LocalConversationSession(
      safeMode: safe,
      recovery: recovery,
      supported: supported,
    );
    sessions.add(session);
    return session;
  }

  void handler(Future<Object?> Function(MethodCall) callback) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return callback(call);
    });
  }

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    safe = ValueNotifier(false);
    recovery = ValueNotifier(null);
    calls = [];
    sessions = [];
    snapshot = {'state': 'idle'};
    handler(
      (call) async => switch (call.method) {
        'start' => 'idle',
        'send' => true,
        'poll' => snapshot,
        _ => null,
      },
    );
  });
  tearDown(() async {
    for (final session in sessions) {
      await session.stop();
      session.dispose();
    }
    await Future<void>.value();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    safe.dispose();
    recovery.dispose();
  });

  testWidgets(
    'idle until explicit choice; only typed text crosses the channel',
    (tester) async {
      final session = create();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, isEmpty);
      expect(await session.reply('not approved'), isNull);
      await session.start();
      snapshot = {'state': 'idle', 'text': 'Hello, from Neura.'};
      final reply = session.reply('typed here');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(await reply, 'Hello, from Neura.');
      expect(calls.map((c) => c.method), ['start', 'send', 'poll']);
      expect(
        calls.singleWhere((c) => c.method == 'send').arguments,
        'typed here',
      );
      expect(
        calls
            .where((c) => c.method != 'send')
            .every((c) => c.arguments == null),
        isTrue,
      );
      await session.stop();
    },
  );

  testWidgets('unsupported platforms never call native or admit a session', (
    tester,
  ) async {
    final session = create(supported: false);
    await session.start();
    expect(session.canStart, isFalse);
    expect(await session.reply('hi'), isNull);
    await session.stop();
    expect(calls, isEmpty);
  });

  testWidgets('UTF-8 input bounds are enforced before sending', (tester) async {
    final session = create();
    await session.start();
    expect(await session.reply('x' * 2049), isNull);
    expect(await session.reply('🧠' * 513), isNull);
    expect(await session.reply(' '), isNull);
    expect(calls.map((c) => c.method), ['start']);
    await session.stop();
  });

  testWidgets('one turn at a time; Stop cancels without queuing a second', (
    tester,
  ) async {
    final session = create();
    await session.start();
    final first = session.reply('first');
    expect(await session.reply('second'), isNull);
    await tester.pump();
    await session.stop();
    expect(await first, isNull);
    expect(calls.where((c) => c.method == 'send').length, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(session.state, LocalConversationState.disabled);
    expect(calls.where((c) => c.method == 'start').length, 1);
  });

  testWidgets(
    'Stop does not wait for a stalled poll and discards its late text',
    (tester) async {
      final gate = Completer<Object?>();
      handler(
        (call) async => switch (call.method) {
          'start' => 'idle',
          'send' => true,
          'poll' => gate.future,
          _ => null,
        },
      );
      final session = create();
      await session.start();
      final reply = session.reply('hello');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await session.stop();
      expect(await reply, isNull);
      expect(calls.last.method, 'stop');
      gate.complete({'state': 'idle', 'text': 'late private reply'});
      await tester.pump();
      expect(session.state, LocalConversationState.disabled);
      expect(session.canSend, isFalse);
    },
  );

  for (final reason in ['Safe Mode', 'recovery']) {
    testWidgets(
      '$reason revokes in-flight text and remains latched on return',
      (tester) async {
        final session = create();
        await session.start();
        final reply = session.reply('private typed text');
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
        expect(await reply, isNull);
        expect(session.state, LocalConversationState.blocked);
        expect(calls.last.method, 'block');
        safe.value = false;
        recovery.value = null;
        session.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await session.start();
        expect(session.canStart, isFalse);
        expect(calls.where((c) => c.method == 'start').length, 1);
      },
    );
  }

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('$state stops and returning needs another explicit start', (
      tester,
    ) async {
      final session = create();
      await session.start();
      final reply = session.reply('hello');
      await tester.pump();
      session.didChangeAppLifecycleState(state);
      await tester.pump();
      expect(await reply, isNull);
      expect(session.state, LocalConversationState.disabled);
      session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(calls.where((c) => c.method == 'start').length, 1);
      expect(session.canStart, isTrue);
    });
  }

  testWidgets('preexisting recovery blocks before any start or submission', (
    tester,
  ) async {
    recovery.value = const NeuraFatalError(source: 'test', phase: 'bootstrap');
    final session = create();
    await session.start();
    await tester.pump();
    expect(session.state, LocalConversationState.blocked);
    expect(calls.map((c) => c.method), ['block']);
  });

  testWidgets('disposal during startup drops its late status and never polls', (
    tester,
  ) async {
    final gate = Completer<Object?>();
    handler((call) async => call.method == 'start' ? gate.future : null);
    final session = create();
    final starting = session.start();
    await tester.pump();
    sessions.remove(session);
    session.dispose();
    await tester.pump();
    gate.complete('idle');
    await starting;
    await tester.pump(const Duration(seconds: 2));
    expect(calls.map((c) => c.method), ['start', 'stop']);
  });

  testWidgets('listener revocation on Start prevents native launch', (
    tester,
  ) async {
    final session = create();
    session.addListener(() {
      if (session.state == LocalConversationState.starting) {
        unawaited(session.stop());
      }
    });
    await session.start();
    await tester.pump();
    expect(calls.map((c) => c.method), ['stop']);
  });

  testWidgets('queued text behind an idle poll is discarded after revocation', (
    tester,
  ) async {
    final gate = Completer<Object?>();
    handler(
      (call) async => switch (call.method) {
        'start' => 'idle',
        'send' => true,
        'poll' => gate.future,
        _ => null,
      },
    );
    final session = create();
    await session.start();
    await tester.pump(const Duration(seconds: 1));
    final reply = session.reply('must not be sent');
    safe.value = true;
    await tester.pump();
    expect(await reply, isNull);
    gate.complete({'state': 'idle'});
    await tester.pump();
    expect(calls.any((c) => c.method == 'send'), isFalse);
  });

  testWidgets('new grants wait for confirmed native Stop', (tester) async {
    final gate = Completer<Object?>();
    handler(
      (call) async => switch (call.method) {
        'start' => 'idle',
        'stop' => gate.future,
        _ => null,
      },
    );
    final session = create();
    await session.start();
    final stopping = session.stop();
    await session.start();
    expect(calls.where((c) => c.method == 'start').length, 1);
    gate.complete(null);
    await stopping;
    await session.start();
    expect(calls.where((c) => c.method == 'start').length, 2);
    await session.stop();
  });

  testWidgets('unconfirmed teardown blocks replacement grants', (tester) async {
    handler((call) async {
      if (call.method == 'stop') {
        throw PlatformException(code: 'failed');
      }
      return call.method == 'start' ? 'idle' : null;
    });
    final session = create();
    await session.start();
    await session.stop();
    await session.start();
    expect(session.state, LocalConversationState.blocked);
    expect(calls.where((c) => c.method == 'start').length, 1);
  });

  for (final invalid in [
    {'state': 'idle', 'text': 'x' * 4097},
    {'state': 'idle'},
    {'state': 'error', 'text': 'untrusted error payload'},
  ]) {
    testWidgets(
      'invalid native response ends the grant without fallback: ${invalid['state']}',
      (tester) async {
        final session = create();
        await session.start();
        snapshot = invalid;
        final reply = session.reply('hello');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(await reply, isNull);
        expect(session.state, LocalConversationState.error);
        expect(calls.last.method, 'stop');
      },
    );
  }

  testWidgets('bounded generation deadline tears down the model owner', (
    tester,
  ) async {
    final session = create();
    await session.start();
    snapshot = {'state': 'working'};
    final reply = session.reply('hello');
    await tester.pump();
    await tester.pump(const Duration(seconds: 120));
    expect(await reply, isNull);
    expect(session.state, LocalConversationState.error);
    expect(calls.last.method, 'stop');
  });
}
