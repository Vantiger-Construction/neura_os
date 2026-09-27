import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_onnx_int4_speech_engine.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/on_device_asr');
  late NeuraOnnxInt4SpeechEngine engine;
  late List<String> calls;

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    calls = [];
    engine = NeuraOnnxInt4SpeechEngine(channel: channel);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'stop' ? 'local transcript' : true;
    });
  });

  tearDown(() async {
    await engine.dispose();
    SafeBoot.instance.safeMode.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final cancellation in ['safe_mode', 'stop', 'dispose']) {
    test('$cancellation invalidates a pending availability check', () async {
      final available = Completer<bool>();
      final checked = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
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

  test('Safe Mode stops a native start before and after its late reply',
      () async {
    final started = Completer<bool>();
    final requested = Completer<void>();
    final stopped = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
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
  });

  test('an available engine starts once and stops normally', () async {
    expect(await engine.start(), isTrue);
    expect(await engine.start(), isTrue);
    expect(engine.isListening, isTrue);
    expect(await engine.stop(), 'local transcript');
    expect(engine.isListening, isFalse);
    expect(calls, ['isAvailable', 'start', 'stop']);
  });
}
