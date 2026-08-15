import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Polls the microphone amplitude every [_kPollInterval] and exposes it as a
/// normalised 0.0–1.0 stream.
///
/// Typical usage:
/// ```dart
/// final mic = NeuraMicDriver();
/// final started = await mic.start();           // requests permission, begins capture
/// if (started) {
///   mic.attachLevel((lvl) {
///     AvatarGlobals.controller.setNumberInput('mic_level', lvl); // per-frame
///     // State transitions go through the event bus so AvatarOrchestrator
///     // and any other listener can react:
///     if (lvl > NeuraMicDriver.kListenThreshold) {
///       NeuraEventBus.I.emit(const NeuraListeningEvent(true));
///     }
///   });
/// }
/// // On dispose:
/// await mic.dispose();
/// ```
class NeuraMicDriver {
  /// Level above which the avatar is considered to be "hearing" the user.
  static const double kListenThreshold = 0.12;

  /// Silence floor in dBFS. Anything at or below this maps to 0.0.
  static const double _kFloor = -50.0;

  static const Duration _kPollInterval = Duration(milliseconds: 80);

  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  StreamSubscription<Uint8List>? _audioSub;
  final StreamController<double> _levelController =
      StreamController<double>.broadcast();

  bool _running = false;

  /// Normalised amplitude stream (0.0 = silence, 1.0 = maximum).
  Stream<double> get level => _levelController.stream;

  /// Whether the driver is currently sampling.
  bool get isRunning => _running;

  /// Requests mic permission and starts amplitude sampling.
  ///
  /// Returns `true` if capture started successfully, `false` if permission
  /// was denied or the recorder failed to start.
  Future<bool> start() async {
    if (_running) return true;
    if (!await _recorder.hasPermission()) return false;

    try {
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      // Drain the PCM stream to prevent buffer build-up on Android/iOS.
      // Amplitude is sampled via getAmplitude() in the timer instead.
      _audioSub = audioStream.listen((_) {});
    } catch (_) {
      await _audioSub?.cancel();
      _audioSub = null;
      return false;
    }

    _running = true;
    _timer = Timer.periodic(_kPollInterval, (_) async {
      if (!_running) return;
      try {
        final amp = await _recorder.getAmplitude();
        // Normalise: -50 dBFS → 0.0, 0 dBFS → 1.0
        final normalised =
            ((amp.current - _kFloor) / (-_kFloor)).clamp(0.0, 1.0);
        _levelController.add(normalised);
      } catch (_) {
        _levelController.add(0.0);
      }
    });
    return true;
  }

  /// Registers [callback] to be called with each amplitude sample (0.0–1.0).
  ///
  /// Preferred wiring pattern (see [NeuraPresenceView] for full state machine):
  /// ```dart
  /// mic.attachLevel((lvl) {
  ///   controller.setNumberInput('mic_level', lvl); // direct – per frame
  ///   if (lvl > NeuraMicDriver.kListenThreshold) {
  ///     NeuraEventBus.I.emit(const NeuraListeningEvent(true));
  ///   }
  ///   // Drive state: idle → listening → thinking → speaking → idle
  /// });
  /// ```
  StreamSubscription<double> attachLevel(void Function(double) callback) {
    return level.listen(callback);
  }

  /// Stops sampling and releases the recorder.
  Future<void> dispose() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _levelController.close();
    await _recorder.dispose();
  }
}
