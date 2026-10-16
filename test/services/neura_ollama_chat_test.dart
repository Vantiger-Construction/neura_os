import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';
import 'package:neuro_companion/startup/neura_error_pipeline.dart';

void main() {
  test('offline editor rejects oversized ASCII and multibyte pastes', () {
    const formatter = NeuraOllamaTextInputFormatter();
    const old = TextEditingValue(text: 'short draft');
    for (final text in ['x' * 1501, '🧠' * 376, 'x${'\u0301' * 750}']) {
      expect(
        formatter.formatEditUpdate(old, TextEditingValue(text: text)),
        old,
      );
    }
    final accepted = TextEditingValue(text: 'x' * 1500);
    expect(formatter.formatEditUpdate(old, accepted), accepted);
  });

  test(
    'visible offline transcript evicts old text by count and UTF-8 bytes',
    () {
      final messages = List.generate(12, (index) => 'turn $index');
      expect(NeuraOllamaChat.firstRetainedVisibleMessage(messages), 4);
      final multibyte = [
        '🧠' * 2000,
        '🧠' * 2000,
        'latest question',
        'latest reply',
      ];
      final first = NeuraOllamaChat.firstRetainedVisibleMessage(multibyte);
      expect(first, 0);
      multibyte.insert(0, 'older text' * 100);
      expect(NeuraOllamaChat.firstRetainedVisibleMessage(multibyte), 1);
      expect(NeuraOllamaChat.firstRetainedVisibleMessage([]), 0);
    },
  );

  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/engine_synthetic_session');
  late ValueNotifier<bool> safe;
  late ValueNotifier<NeuraFatalError?> recovery;
  late List<MethodCall> calls;
  late NeuraOllamaChat chat;
  var elapsed = Duration.zero;

  Future<String> reply(NeuraGenerationCancel cancel) => chat.reply(
    system: 'Neura charter',
    messages: [
      {'role': 'user', 'content': 'Hello'},
    ],
    cancel: cancel,
  );

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    safe = ValueNotifier(false);
    recovery = ValueNotifier(null);
    calls = [];
    elapsed = Duration.zero;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'beginOllama' => 1,
        'pollOllama' => "Hi, I'm Neura.",
        _ => null,
      };
    });
    chat = NeuraOllamaChat(
      safeMode: safe,
      recovery: recovery,
      supported: true,
      monotonicNow: () => elapsed,
    );
  });
  tearDown(() {
    chat.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    safe.dispose();
    recovery.dispose();
  });

  testWidgets('explicit local chat forwards only charter and visible text', (
    tester,
  ) async {
    expect(calls, isEmpty);
    expect(await reply(NeuraGenerationCancel('one')), "Hi, I'm Neura.");
    final request =
        jsonDecode(calls.first.arguments as String) as Map<String, dynamic>;
    expect(request.keys.toSet(), {'system', 'messages'});
    expect(request['system'], 'Neura charter');
    expect(calls.map((c) => c.method), [
      'beginOllama',
      'pollOllama',
      'cancelOllama',
    ]);
  });

  Map<String, dynamic> nativeTiming({int outcome = 1}) => {
    'version': 1,
    'outcome': outcome,
    'preflightUs': 20000,
    'inferenceUs': 100000,
    'deliveryUs': outcome == 1 ? 25000 : null,
    'cancellationUs': outcome == 3 ? 15000 : null,
    'totalUs': 145000,
  };

  testWidgets('synthetic timings separate phases and include final delivery', (
    tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'beginOllama':
          elapsed = const Duration(milliseconds: 5);
          return 7;
        case 'pollOllama':
          elapsed = const Duration(milliseconds: 150);
          return 'Synthetic answer';
        case 'cancelOllama':
          elapsed = const Duration(milliseconds: 165);
          return null;
        case 'readOllamaTiming':
          return nativeTiming();
      }
      return null;
    });
    expect(await chat.readLatency(), isNull);
    await reply(NeuraGenerationCancel('synthetic'));
    // Reading is explicit; response completion adds no monitoring calls.
    expect(calls.map((c) => c.method), [
      'beginOllama',
      'pollOllama',
      'cancelOllama',
    ]);
    final timing = (await chat.readLatency())!;
    expect(timing.outcome, NeuraOllamaLatencyOutcome.delivered);
    expect(timing.preflight, const Duration(milliseconds: 20));
    expect(timing.inference, const Duration(milliseconds: 100));
    expect(timing.delivery, const Duration(milliseconds: 25));
    expect(timing.total, const Duration(milliseconds: 165));
    expect(timing.nativeTotal, const Duration(milliseconds: 145));
    expect(timing.cancellation, isNull);
    chat.clearLatency();
    expect(await chat.readLatency(), isNull);
  });

  testWidgets(
    'synthetic cancellation includes delayed native start and cleanup',
    (tester) async {
      final start = Completer<int>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'beginOllama') return start.future;
        if (call.method == 'cancelOllama') {
          elapsed = const Duration(milliseconds: 85);
        }
        if (call.method == 'readOllamaTiming') return nativeTiming(outcome: 3);
        return null;
      });
      final cancel = NeuraGenerationCancel('cancel-timing');
      final expected = expectLater(
        reply(cancel),
        throwsA(isA<NeuraGenerationCancelled>()),
      );
      await tester.pump();
      elapsed = const Duration(milliseconds: 50);
      cancel.cancel();
      await tester.pump();
      elapsed = const Duration(milliseconds: 80);
      start.complete(8);
      await tester.pump();
      await expected;
      final timing = (await chat.readLatency())!;
      expect(timing.outcome, NeuraOllamaLatencyOutcome.cancelled);
      expect(timing.total, const Duration(milliseconds: 85));
      expect(timing.cancellation, const Duration(milliseconds: 35));
      expect(timing.nativeCancellation, const Duration(milliseconds: 15));
      expect(timing.delivery, isNull);
      expect(calls.where((call) => call.method == 'pollOllama'), isEmpty);
    },
  );

  for (final reason in ['background', 'safe', 'recovery', 'dispose', 'clear']) {
    testWidgets('$reason clears timing and suppresses a pending timing read', (
      tester,
    ) async {
      final pending = Completer<Map<String, dynamic>>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'beginOllama') return 9;
        if (call.method == 'pollOllama') return 'Synthetic answer';
        if (call.method == 'readOllamaTiming') return pending.future;
        return null;
      });
      await reply(NeuraGenerationCancel('before-clear'));
      final read = chat.readLatency();
      await tester.pump();
      switch (reason) {
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          break;
        case 'safe':
          safe.value = true;
          break;
        case 'recovery':
          recovery.value = const NeuraFatalError(
            source: 'synthetic',
            phase: 'runtime',
          );
          break;
        case 'dispose':
          chat.dispose();
          break;
        case 'clear':
          chat.clearLatency();
          break;
      }
      pending.complete(nativeTiming());
      await tester.pump();
      expect(await read, isNull);
      expect(await chat.readLatency(), isNull);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(await chat.readLatency(), isNull);
    });
  }

  testWidgets('timing rejects unexpected fields and daemon text', (
    tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'beginOllama') return 10;
      if (call.method == 'pollOllama') return 'Synthetic answer';
      if (call.method == 'readOllamaTiming') {
        return {...nativeTiming(), 'prompt': 'must never reach a receipt'};
      }
      return null;
    });
    await reply(NeuraGenerationCancel('schema'));
    expect(await chat.readLatency(), isNull);
  });

  testWidgets('cancellation during final delivery suppresses the reply', (
    tester,
  ) async {
    final cleanup = Completer<void>();
    final cancel = NeuraGenerationCancel('delivery-race');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'beginOllama') return 11;
      if (call.method == 'pollOllama') return 'Must be discarded';
      if (call.method == 'cancelOllama') return cleanup.future;
      return null;
    });
    final expected = expectLater(
      reply(cancel),
      throwsA(isA<NeuraGenerationCancelled>()),
    );
    await tester.pump();
    cancel.cancel();
    cleanup.complete();
    await tester.pump();
    await expected;
  });

  for (final reason in ['cancel', 'background', 'safe', 'dispose']) {
    testWidgets('$reason discards a late native start and cancels its id', (
      tester,
    ) async {
      final lateStart = Completer<int>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'beginOllama') return lateStart.future;
        return null;
      });
      final cancel = NeuraGenerationCancel(reason);
      final result = reply(cancel);
      final expected = expectLater(
        result,
        throwsA(isA<NeuraGenerationCancelled>()),
      );
      await tester.pump();
      switch (reason) {
        case 'cancel':
          cancel.cancel();
          break;
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          break;
        case 'safe':
          safe.value = true;
          break;
        case 'dispose':
          chat.dispose();
          break;
      }
      lateStart.complete(42);
      await tester.pump();
      await expected;
      expect(calls.where((c) => c.method == 'pollOllama'), isEmpty);
      expect(
        calls
            .where((c) => c.method == 'cancelOllama')
            .every((c) => c.arguments == 42),
        isTrue,
      );
      expect(calls.where((c) => c.method == 'cancelOllama'), isNotEmpty);
    });
  }

  testWidgets('Safe Mode remains blocked after it clears', (tester) async {
    safe.value = true;
    await tester.pump();
    safe.value = false;
    await expectLater(reply(NeuraGenerationCancel('two')), throwsStateError);
    expect(calls.where((c) => c.method == 'beginOllama'), isEmpty);
    expect(calls.where((c) => c.method == 'blockOllama'), hasLength(1));
  });

  testWidgets('cancellation suppresses an already pending native reply', (
    tester,
  ) async {
    final lateReply = Completer<String>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'beginOllama') return 9;
      if (call.method == 'pollOllama') return lateReply.future;
      return null;
    });
    final cancel = NeuraGenerationCancel('late-poll');
    final result = reply(cancel);
    final expected = expectLater(
      result,
      throwsA(isA<NeuraGenerationCancelled>()),
    );
    await tester.pump();
    expect(calls.where((c) => c.method == 'pollOllama'), hasLength(1));
    cancel.cancel();
    lateReply.complete('Stale answer');
    await tester.pump();
    await expected;
    expect(calls.where((c) => c.method == 'cancelOllama'), isNotEmpty);
  });

  testWidgets(
    'failed local inference reports a fixed error with no cloud call',
    (tester) async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        throw PlatformException(
          code: 'failed',
          message: 'private daemon error',
        );
      });
      await expectLater(
        reply(NeuraGenerationCancel('three')),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.toString().contains('No cloud request') &&
                !e.toString().contains('private daemon error'),
          ),
        ),
      );
      expect(calls.map((c) => c.method), ['beginOllama']);
    },
  );
}
