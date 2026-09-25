import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_speech_benchmark.dart';
import 'package:neuro_companion/services/neura_speech_engine.dart';

final class _Probe implements NeuraSpeechBenchmarkProbe {
  var reads = 0;

  @override
  Future<int?> residentSetBytes() async => reads++ == 0 ? 1000 : 1400;

  @override
  Future<NeuraThermalState> thermalState() async => NeuraThermalState.nominal;
}

final class _FakeEngine implements NeuraSpeechEngine {
  final controller = StreamController<NeuraSpeechSegment>.broadcast();
  var listening = false;

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
}
