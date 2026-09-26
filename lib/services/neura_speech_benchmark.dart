import 'dart:async';

import 'neura_speech_engine.dart';

enum NeuraThermalState { nominal, fair, serious, critical, unavailable }

abstract interface class NeuraSpeechBenchmarkProbe {
  Future<int?> residentSetBytes();
  Future<NeuraThermalState> thermalState();
}

final class NeuraSpeechBenchmarkResult {
  const NeuraSpeechBenchmarkResult({
    required this.engineId,
    required this.started,
    required this.completed,
    required this.startLatency,
    required this.firstFinalLatency,
    required this.stopLatency,
    required this.rssDeltaBytes,
    required this.packageBytes,
    required this.thermalBefore,
    required this.thermalAfter,
    this.failureKind,
  });

  final String engineId;
  final bool started;
  final bool completed;
  final Duration startLatency;
  final Duration? firstFinalLatency;
  final Duration stopLatency;
  final int? rssDeltaBytes;
  final int? packageBytes;
  final NeuraThermalState thermalBefore;
  final NeuraThermalState thermalAfter;
  final String? failureKind;

  Map<String, Object?> toJson() => {
        'engine_id': engineId,
        'started': started,
        'completed': completed,
        'start_latency_ms': startLatency.inMilliseconds,
        'first_final_latency_ms': firstFinalLatency?.inMilliseconds,
        'stop_latency_ms': stopLatency.inMilliseconds,
        'rss_delta_bytes': rssDeltaBytes,
        'package_bytes': packageBytes,
        'thermal_before': thermalBefore.name,
        'thermal_after': thermalAfter.name,
        'failure_kind': failureKind,
      };
}

/// Device benchmark harness. It records operational measurements only and
/// intentionally discards recognized text.
final class NeuraSpeechBenchmarkHarness {
  NeuraSpeechBenchmarkHarness({
    required bool Function() safeModeReader,
    required NeuraSpeechBenchmarkProbe probe,
  })  : _safeModeReader = safeModeReader,
        _probe = probe;

  final bool Function() _safeModeReader;
  final NeuraSpeechBenchmarkProbe _probe;

  Future<NeuraSpeechBenchmarkResult> run({
    required NeuraSpeechEngine engine,
    required Future<void> Function() exercise,
    required Duration timeout,
    int? packageBytes,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    if (packageBytes != null && packageBytes < 0) {
      throw ArgumentError.value(
        packageBytes,
        'packageBytes',
        'Must not be negative.',
      );
    }
    if (_safeModeReader()) {
      throw StateError('Speech benchmarks are blocked in Safe Mode.');
    }
    if (!engine.capabilities.onDevice) {
      throw StateError('Speech benchmark requires an on-device engine.');
    }
    if (!await engine.isAvailable()) {
      return NeuraSpeechBenchmarkResult(
        engineId: engine.id,
        started: false,
        completed: false,
        startLatency: Duration.zero,
        firstFinalLatency: null,
        stopLatency: Duration.zero,
        rssDeltaBytes: null,
        packageBytes: packageBytes,
        thermalBefore: NeuraThermalState.unavailable,
        thermalAfter: NeuraThermalState.unavailable,
        failureKind: 'unavailable',
      );
    }

    final rssBefore = await _probe.residentSetBytes();
    final thermalBefore = await _probe.thermalState();
    final finalSegment = Completer<void>();
    final clock = Stopwatch()..start();
    final subscription = engine.segments.listen((segment) {
      if (segment.isFinal && !finalSegment.isCompleted) {
        finalSegment.complete();
      }
    });
    var started = false;
    Duration? firstFinalLatency;
    String? failureKind;
    var startLatency = Duration.zero;
    var stopLatency = Duration.zero;
    try {
      final startClock = Stopwatch()..start();
      started = await engine.start();
      startClock.stop();
      startLatency = startClock.elapsed;
      if (!started) {
        failureKind = 'start_failed';
      } else {
        await exercise();
        if (_safeModeReader()) {
          failureKind = 'safe_mode';
        } else {
          try {
            await finalSegment.future.timeout(timeout);
            firstFinalLatency = clock.elapsed;
          } on TimeoutException {
            failureKind = 'timeout';
          }
        }
      }
    } finally {
      final stopClock = Stopwatch()..start();
      await engine.stop();
      stopClock.stop();
      stopLatency = stopClock.elapsed;
      await subscription.cancel();
      clock.stop();
    }

    final rssAfter = await _probe.residentSetBytes();
    final thermalAfter = await _probe.thermalState();
    return NeuraSpeechBenchmarkResult(
      engineId: engine.id,
      started: started,
      completed: started && firstFinalLatency != null && failureKind == null,
      startLatency: startLatency,
      firstFinalLatency: firstFinalLatency,
      stopLatency: stopLatency,
      rssDeltaBytes:
          rssBefore == null || rssAfter == null ? null : rssAfter - rssBefore,
      packageBytes: packageBytes,
      thermalBefore: thermalBefore,
      thermalAfter: thermalAfter,
      failureKind: failureKind,
    );
  }
}
