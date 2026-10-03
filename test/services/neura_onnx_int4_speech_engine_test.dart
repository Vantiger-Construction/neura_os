import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_onnx_int4_speech_engine.dart';
import 'package:neuro_companion/services/neura_speech_benchmark.dart';
import 'package:neuro_companion/services/neura_speech_engine.dart';

final class _OfflineProbe implements NeuraSpeechBenchmarkProbe {
  @override
  Future<int?> residentSetBytes() async => null;

  @override
  Future<NeuraThermalState> thermalState() async =>
      NeuraThermalState.unavailable;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/on_device_asr');
  late NeuraOnnxInt4SpeechEngine engine;
  late List<String> calls;

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    calls = [];
    engine = NeuraOnnxInt4SpeechEngine(channel: channel);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'stop' ? 'local transcript' : true;
    });
  });

  tearDown(() async {
    await engine.dispose();
    SafeBoot.instance.safeMode.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> sendNativeSegment(Map<String, Object?> arguments) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onSegment', arguments),
      ),
      (_) {},
    );
    await pumpEventQueue();
  }

  test('an unavailable native backend cannot start capture', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return false;
    });

    expect(await engine.isAvailable(), isFalse);
    expect(await engine.start(), isFalse);
    expect(engine.isListening, isFalse);
    expect(calls, ['isAvailable', 'isAvailable']);
  });

  test('native onSegment maps only while local capture is active', () async {
    final received = <NeuraSpeechSegment>[];
    final subscription = engine.segments.listen(received.add);

    expect(await engine.start(), isTrue);
    await sendNativeSegment({
      'text': 'kept on this device',
      'is_final': false,
      'pause_ms': 125,
    });

    expect(received, hasLength(1));
    final segment = received.single;
    expect(segment.text, 'kept on this device');
    expect(segment.isFinal, isFalse);
    expect(segment.confidence, isNull);
    expect(segment.pauseBefore, const Duration(milliseconds: 125));

    await engine.stop();
    await sendNativeSegment({'text': 'late native result', 'is_final': true});
    expect(received, hasLength(1));
    await subscription.cancel();
  });

  test(
    'Safe Mode begins teardown and discards queued native segments',
    () async {
      final stopReply = Completer<String>();
      final stopRequested = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'stop') {
          expect(call.arguments, {'discard': true});
          if (!stopRequested.isCompleted) stopRequested.complete();
          return stopReply.future;
        }
        return true;
      });
      final received = <NeuraSpeechSegment>[];
      final subscription = engine.segments.listen(received.add);

      expect(await engine.start(), isTrue);
      SafeBoot.instance.safeMode.value = true;
      await stopRequested.future;
      expect(engine.isListening, isFalse);

      await sendNativeSegment({'text': 'must be discarded', 'is_final': true});
      expect(received, isEmpty);

      stopReply.complete('discarded by caller');
      await pumpEventQueue();
      await subscription.cancel();
    },
  );

  for (final cancellation in ['safe_mode', 'stop', 'dispose']) {
    test('$cancellation invalidates a pending availability check', () async {
      final available = Completer<bool>();
      final checked = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'isAvailable') {
          checked.complete();
          return available.future;
        }
        return true;
      });

      final starting = engine.start();
      await checked.future;
      switch (cancellation) {
        case 'safe_mode':
          SafeBoot.instance.safeMode.value = true;
          // Leaving Safe Mode must not revive an earlier start request.
          SafeBoot.instance.safeMode.value = false;
          break;
        case 'stop':
          await engine.stop();
          break;
        case 'dispose':
          await engine.dispose();
          break;
      }
      available.complete(true);

      expect(await starting, isFalse);
      expect(engine.isListening, isFalse);
      expect(calls, ['isAvailable']);
    });
  }

  test(
    'Safe Mode stops a native start before and after its late reply',
    () async {
      final started = Completer<bool>();
      final requested = Completer<void>();
      final stopped = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'start') {
          requested.complete();
          return started.future;
        }
        if (call.method == 'stop') {
          if (!stopped.isCompleted) stopped.complete();
          return '';
        }
        return true;
      });

      final starting = engine.start();
      await requested.future;
      SafeBoot.instance.safeMode.value = true;
      await stopped.future;
      expect(engine.isListening, isFalse);
      started.complete(true);

      expect(await starting, isFalse);
      expect(engine.isListening, isFalse);
      expect(calls, ['isAvailable', 'start', 'stop', 'stop']);
    },
  );

  test('an available engine starts once and stops normally', () async {
    expect(await engine.start(), isTrue);
    expect(await engine.start(), isTrue);
    expect(engine.isListening, isTrue);
    expect(await engine.stop(), 'local transcript');
    expect(engine.isListening, isFalse);
    expect(calls, ['isAvailable', 'start', 'stop']);
  });

  test('restart waits for the native stop acknowledgement', () async {
    final reply = Completer<String>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'stop' ? reply.future : true;
    });

    expect(await engine.start(), isTrue);
    final stopping = engine.stop();
    await pumpEventQueue();
    expect(await engine.start(), isFalse);
    reply.complete('local transcript');
    expect(await stopping, 'local transcript');
    expect(await engine.start(), isTrue);
  });

  test(
    'dispose waits for a late native start and the second discard',
    () async {
      final startReply = Completer<bool>();
      final requested = Completer<void>();
      final lateStopReply = Completer<String>();
      var stops = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'start') {
          requested.complete();
          return startReply.future;
        }
        if (call.method == 'stop') {
          expect(call.arguments, {'discard': true});
          stops++;
          return stops == 1 ? '' : lateStopReply.future;
        }
        return true;
      });

      final starting = engine.start();
      await requested.future;
      var disposed = false;
      final disposing = engine.dispose().then((_) => disposed = true);
      await pumpEventQueue();
      expect(stops, 1);
      expect(disposed, isFalse);
      startReply.complete(true);
      await pumpEventQueue();
      expect(stops, 2);
      expect(disposed, isFalse);
      lateStopReply.complete('must be discarded');
      expect(await starting, isFalse);
      await disposing;
      expect(disposed, isTrue);
    },
  );

  test('transient Safe Mode invalidates a normal stop transcript', () async {
    final reply = Completer<String>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      return call.method == 'stop' ? reply.future : true;
    });

    expect(await engine.start(), isTrue);
    final stopping = engine.stop();
    await pumpEventQueue();
    SafeBoot.instance.safeMode.value = true;
    SafeBoot.instance.safeMode.value = false;
    reply.complete('private tail');
    expect(await stopping, isEmpty);
  });

  test('channel benchmark discards both callbacks and stop text offline', () {
    return HttpOverrides.runZoned(
      () async {
        final registry = NeuraSpeechEngineRegistry()..register(engine);
        expect(await registry.select(platform: 'windows'), isNull);
        expect(calls, isEmpty);
        final harness = NeuraSpeechBenchmarkHarness(
          safeModeReader: () => SafeBoot.instance.safeMode.value,
          probe: _OfflineProbe(),
        );
        final result = await harness.run(
          engine: engine,
          exercise: () => sendNativeSegment({
            'text': 'synthetic secret phrase',
            'is_final': true,
          }),
          timeout: const Duration(seconds: 1),
        );

        expect(result.completed, isTrue);
        expect(engine.isListening, isFalse);
        expect(result.toJson().toString(), isNot(contains('synthetic secret')));
        expect(result.toJson().toString(), isNot(contains('local transcript')));
        expect(calls, ['isAvailable', 'isAvailable', 'start', 'stop']);
      },
      createHttpClient: (_) {
        throw StateError('Network is forbidden in the speech benchmark test.');
      },
    );
  });
}
