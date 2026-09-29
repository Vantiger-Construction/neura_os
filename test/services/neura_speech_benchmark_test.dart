import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_speech_benchmark.dart';
import 'package:neuro_companion/services/neura_speech_engine.dart';

final class _Probe implements NeuraSpeechBenchmarkProbe {
  _Probe({this.onThermalRead});

  final void Function()? onThermalRead;
  var reads = 0;

  @override
  Future<int?> residentSetBytes() async => reads++ == 0 ? 1000 : 1400;

  @override
  Future<NeuraThermalState> thermalState() async {
    onThermalRead?.call();
    return NeuraThermalState.nominal;
  }
}

final class _FakeEngine implements NeuraSpeechEngine {
  final controller = StreamController<NeuraSpeechSegment>.broadcast();
  var listening = false;
  var starts = 0;

  @override
  NeuraSpeechEngineCapabilities get capabilities =>
      const NeuraSpeechEngineCapabilities(
        onDevice: true,
        supportsPartialResults: true,
        supportsConfidence: true,
        supportedPlatforms: {'test'},
      );

  @override
  String get id => 'fake';

  @override
  bool get isListening => listening;

  @override
  Stream<NeuraSpeechSegment> get segments => controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> start() async {
    starts++;
    listening = true;
    return true;
  }

  @override
  Future<String> stop() async {
    listening = false;
    return '';
  }
}

void main() {
  test('records device metrics without retaining transcript', () async {
    final engine = _FakeEngine();
    final harness = NeuraSpeechBenchmarkHarness(
      safeModeReader: () => false,
      probe: _Probe(),
    );

    final result = await harness.run(
      engine: engine,
      exercise: () async {
        engine.controller.add(
          NeuraSpeechSegment(
            engineId: engine.id,
            text: 'private benchmark phrase',
            isFinal: true,
            observedAtUtc: DateTime.utc(2026, 9, 25),
            confidence: 0.9,
          ),
        );
      },
      timeout: const Duration(seconds: 1),
      packageBytes: 1234,
    );

    expect(result.completed, isTrue);
    expect(result.rssDeltaBytes, 400);
    expect(result.packageBytes, 1234);
    expect(result.toJson().toString(), isNot(contains('private benchmark')));
    await engine.controller.close();
  });

  test('Safe Mode blocks before probing or starting the microphone', () async {
    final engine = _FakeEngine();
    final harness = NeuraSpeechBenchmarkHarness(
      safeModeReader: () => true,
      probe: _Probe(),
    );

    await expectLater(
      harness.run(
        engine: engine,
        exercise: () async {},
        timeout: const Duration(milliseconds: 1),
      ),
      throwsStateError,
    );
    expect(engine.isListening, isFalse);
    await engine.controller.close();
  });

  test('invalid measurement bounds fail before touching the engine', () async {
    final engine = _FakeEngine();
    final harness = NeuraSpeechBenchmarkHarness(
      safeModeReader: () => false,
      probe: _Probe(),
    );

    await expectLater(
      harness.run(
        engine: engine,
        exercise: () async {},
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(engine.isListening, isFalse);
    await engine.controller.close();
  });

  test('Safe Mode entered during probing prevents microphone start', () async {
    final engine = _FakeEngine();
    var safeMode = false;
    final harness = NeuraSpeechBenchmarkHarness(
      safeModeReader: () => safeMode,
      probe: _Probe(onThermalRead: () => safeMode = true),
    );

    await expectLater(
      harness.run(
        engine: engine,
        exercise: () async {},
        timeout: const Duration(seconds: 1),
      ),
      throwsStateError,
    );
    expect(engine.starts, 0);
    await engine.controller.close();
  });

  test('first-final latency is captured before the exercise ends', () async {
    final engine = _FakeEngine();
    final harness = NeuraSpeechBenchmarkHarness(
      safeModeReader: () => false,
      probe: _Probe(),
    );
    final clock = Stopwatch()..start();
    late Duration receivedBy;

    final result = await harness.run(
      engine: engine,
      exercise: () async {
        engine.controller.add(
          NeuraSpeechSegment(
            engineId: engine.id,
            text: 'discard this phrase',
            isFinal: true,
            observedAtUtc: DateTime.utc(2026, 9, 27),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        receivedBy = clock.elapsed;
        await Future<void>.delayed(
          receivedBy + const Duration(milliseconds: 50),
        );
      },
      timeout: const Duration(seconds: 5),
    );

    expect(result.completed, isTrue);
    expect(result.firstFinalLatency, lessThanOrEqualTo(receivedBy));
    clock.stop();
    await engine.controller.close();
  });

  test('an unfinished exercise times out and stops the microphone', () async {
    final engine = _FakeEngine();
    final exercise = Completer<void>();
    final harness = NeuraSpeechBenchmarkHarness(
      safeModeReader: () => false,
      probe: _Probe(),
    );

    final result = await harness
        .run(
          engine: engine,
          exercise: () => exercise.future,
          timeout: const Duration(milliseconds: 10),
        )
        .timeout(const Duration(seconds: 1));

    expect(result.completed, isFalse);
    expect(result.failureKind, 'timeout');
    expect(engine.isListening, isFalse);
    exercise.complete();
    await engine.controller.close();
  });
}
