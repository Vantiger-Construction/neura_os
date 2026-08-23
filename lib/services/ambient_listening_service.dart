import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/memory/memory_crypto.dart';
import '../mascot/mascot_window_service.dart';
import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';
import 'ambient_listening_prefs.dart';
import 'neura_tts_service.dart';

/// The proactive greeting remains disabled because the first native Windows
/// TTS call can race the floating mascot engine and terminate the process.
const bool kEnableProactiveGreetingTts = false;

/// Opt-in, voice-activity-triggered ambient recording encrypted at rest.
class AmbientListeningService {
  AmbientListeningService._() {
    AmbientListeningPrefsController.instance.enabled.addListener(
      _onPrefChanged,
    );
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  static final AmbientListeningService instance = AmbientListeningService._();

  bool get captureAllowed => !SafeBoot.instance.safeMode.value;

  bool get _captureRequested =>
      captureAllowed && AmbientListeningPrefsController.instance.enabled.value;

  static const double _kListenThreshold = 0.12;
  static const double _kFloor = -50.0;
  static const Duration _kPollInterval = Duration(milliseconds: 80);
  static const Duration _kPreRoll = Duration(milliseconds: 700);
  static const Duration _kPostRollSilence = Duration(milliseconds: 800);
  static const Duration _kMinUtterance = Duration(milliseconds: 400);
  static const Duration _kMaxUtterance = Duration(minutes: 2);
  static const int _sampleRate = 16000;
  static const int _bytesPerSample = 2;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _amplitudeTimer;
  Timer? _silenceTimer;

  bool _running = false;
  bool _starting = false;
  bool _capturing = false;
  bool _pollInFlight = false;
  int _lifecycleGeneration = 0;
  Future<void>? _stopInFlight;

  final Queue<Uint8List> _preRollBuffer = Queue<Uint8List>();
  int _preRollBytes = 0;
  final BytesBuilder _utteranceBuffer = BytesBuilder(copy: false);
  int _utteranceStartMs = 0;

  MemoryCrypto? _crypto;
  Future<void> _persistQueue = Future<void>.value();
  int _dataGeneration = 0;

  final ValueNotifier<bool> isLive = ValueNotifier<bool>(false);

  int get _preRollCapBytes =>
      (_kPreRoll.inMilliseconds / 1000 * _sampleRate * _bytesPerSample).round();

  bool _startStillWanted(int generation) =>
      generation == _lifecycleGeneration && _captureRequested;

  bool _persistStillAllowed(int generation) =>
      generation == _dataGeneration && _running && _captureRequested;

  void _onPrefChanged() {
    if (_captureRequested) {
      if (!_running && !_starting) {
        _runLifecycle(start(), 'ambient_listening_pref_start_failed');
      }
      return;
    }
    if (_running || _starting) {
      _runLifecycle(stop(), 'ambient_listening_pref_stop_failed');
    }
  }

  void _onSafeModeChanged() {
    if (!captureAllowed && (_running || _starting)) {
      _runLifecycle(stop(), 'ambient_listening_safe_mode_stop_failed');
    }
  }

  void _runLifecycle(Future<void> operation, String logKey) {
    unawaited(_guardLifecycle(operation, logKey));
  }

  Future<void> _guardLifecycle(Future<void> operation, String logKey) async {
    try {
      await operation;
    } catch (error, stack) {
      try {
        await AppLog.instance.caught(logKey, error, stack);
      } catch (_) {}
    }
  }

  Future<void> greetAndStartListening() async {
    if (!captureAllowed) return;
    await MascotWindowService.I.initialCreationSettled;
    if (!captureAllowed) return;

    if (kEnableProactiveGreetingTts) {
      try {
        await NeuraTtsService.instance
            .speak("Hi. I'm Neura. I'm here if you need me.")
            .timeout(const Duration(seconds: 5));
      } catch (error, stack) {
        await AppLog.instance.caught('ambient_greet_failed', error, stack);
      }
    }

    if (_captureRequested) await start();
  }

  Future<void> start() async {
    if (_running || _starting || !_captureRequested) return;

    final stopping = _stopInFlight;
    if (stopping != null) await stopping;
    if (_running || _starting || !_captureRequested) return;

    _starting = true;
    final generation = ++_lifecycleGeneration;
    var invalidated = false;
    StreamSubscription<Uint8List>? newSubscription;
    final recorder = _recorder ??= AudioRecorder();

    try {
      if (!await recorder.hasPermission()) {
        await AppLog.instance.warn('ambient_listening_no_mic_permission');
        return;
      }
      if (!_startStillWanted(generation)) {
        invalidated = true;
        return;
      }

      final audioStream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      if (!_startStillWanted(generation)) {
        invalidated = true;
        try {
          await recorder.stop();
        } catch (_) {}
        return;
      }

      final subscription = audioStream.listen(
        _onAudioChunk,
        onError: (Object error, StackTrace stack) {
          _runLifecycle(
            _handleAudioStreamError(error, stack),
            'ambient_listening_stream_shutdown_failed',
          );
        },
      );
      newSubscription = subscription;
      if (!_startStillWanted(generation)) {
        invalidated = true;
        await subscription.cancel();
        newSubscription = null;
        try {
          await recorder.stop();
        } catch (_) {}
        return;
      }

      _audioSub = subscription;
      newSubscription = null;
      _running = true;
      _amplitudeTimer = Timer.periodic(_kPollInterval, (_) {
        _runLifecycle(_pollAmplitude(), 'ambient_listening_poll_failed');
      });
    } catch (error, stack) {
      try {
        await newSubscription?.cancel();
      } catch (_) {}
      try {
        await recorder.stop();
      } catch (_) {}
      await AppLog.instance.caught(
        'ambient_listening_start_failed',
        error,
        stack,
      );
    } finally {
      invalidated = invalidated || generation != _lifecycleGeneration;
      _starting = false;
      if (invalidated && _captureRequested && !_running) {
        _runLifecycle(start(), 'ambient_listening_restart_after_toggle_failed');
      }
    }
  }

  Future<void> _handleAudioStreamError(Object error, StackTrace stack) async {
    try {
      await AppLog.instance.caught(
        'ambient_listening_stream_failed',
        error,
        stack,
      );
    } finally {
      await stop();
    }
  }

  Future<void> stop() {
    final existing = _stopInFlight;
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = _stopOnce().whenComplete(() {
      if (identical(_stopInFlight, operation)) _stopInFlight = null;
    });
    _stopInFlight = operation;
    return operation;
  }

  Future<void> _stopOnce() async {
    _lifecycleGeneration += 1;
    _dataGeneration += 1;
    _running = false;
    _capturing = false;
    isLive.value = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    Object? cleanupError;
    StackTrace? cleanupStack;

    final subscription = _audioSub;
    _audioSub = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (error, stack) {
        cleanupError = error;
        cleanupStack = stack;
      }
    }

    _preRollBuffer.clear();
    _preRollBytes = 0;
    _utteranceBuffer.clear();

    try {
      await _recorder?.stop();
    } catch (error, stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    }

    final error = cleanupError;
    if (error != null) {
      Error.throwWithStackTrace(error, cleanupStack ?? StackTrace.current);
    }
  }

  Future<void> resetAfterDataWipe() async {
    Object? cleanupError;
    StackTrace? cleanupStack;

    try {
      await stop();
    } catch (error, stack) {
      cleanupError = error;
      cleanupStack = stack;
    }

    try {
      await _persistQueue;
    } catch (error, stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    } finally {
      _crypto = null;
    }

    final error = cleanupError;
    if (error != null) {
      Error.throwWithStackTrace(error, cleanupStack ?? StackTrace.current);
    }
  }

  void _onAudioChunk(Uint8List chunk) {
    if (!_running || !_captureRequested) return;

    if (_capturing) {
      _utteranceBuffer.add(chunk);
      final elapsedMs =
          DateTime.now().millisecondsSinceEpoch - _utteranceStartMs;
      if (elapsedMs >= _kMaxUtterance.inMilliseconds) {
        _runLifecycle(
          _finalizeUtterance(),
          'ambient_listening_forced_finalize_failed',
        );
      }
      return;
    }

    _preRollBuffer.add(chunk);
    _preRollBytes += chunk.length;
    while (_preRollBytes > _preRollCapBytes && _preRollBuffer.isNotEmpty) {
      _preRollBytes -= _preRollBuffer.removeFirst().length;
    }
  }

  Future<void> _pollAmplitude() async {
    if (_pollInFlight || !_running) return;
    _pollInFlight = true;
    final generation = _lifecycleGeneration;

    try {
      if (!_captureRequested) {
        await stop();
        return;
      }

      double normalized;
      try {
        final recorder = _recorder;
        if (recorder == null) return;
        final amplitude = await recorder.getAmplitude();
        normalized = ((amplitude.current - _kFloor) / (-_kFloor)).clamp(
          0.0,
          1.0,
        );
      } catch (_) {
        normalized = 0.0;
      }

      if (!_running ||
          !_captureRequested ||
          generation != _lifecycleGeneration) {
        return;
      }

      if (normalized <= _kListenThreshold) return;

      _silenceTimer?.cancel();
      _silenceTimer = Timer(_kPostRollSilence, () {
        _runLifecycle(
          _finalizeUtterance(),
          'ambient_listening_silence_finalize_failed',
        );
      });

      if (_capturing) return;

      _capturing = true;
      isLive.value = true;
      _utteranceStartMs = DateTime.now().millisecondsSinceEpoch;
      _utteranceBuffer.clear();
      for (final chunk in _preRollBuffer) {
        _utteranceBuffer.add(chunk);
      }
      _preRollBuffer.clear();
      _preRollBytes = 0;
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _finalizeUtterance() async {
    if (!_capturing || !_running || !_captureRequested) return;

    _capturing = false;
    isLive.value = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;

    final pcm = _utteranceBuffer.takeBytes();
    final durationMs = (pcm.length / _bytesPerSample / _sampleRate * 1000)
        .round();
    if (durationMs < _kMinUtterance.inMilliseconds) return;

    final generation = _dataGeneration;
    try {
      final wav = _wrapWav(pcm);
      final next = _persistQueue.then((_) async {
        if (!_persistStillAllowed(generation)) return;
        await _persist(wav, durationMs, generation);
      });
      _persistQueue = next.then<void>((_) {}, onError: (_) {});
      await next;
    } catch (error, stack) {
      await AppLog.instance.caught(
        'ambient_listening_persist_failed',
        error,
        stack,
      );
    }
  }

  Uint8List _wrapWav(Uint8List pcm) {
    const bitsPerSample = 16;
    const channels = 1;
    final byteRate = _sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    final header = ByteData(44);
    void writeString(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeString(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);

    final output = BytesBuilder(copy: false);
    output.add(header.buffer.asUint8List());
    output.add(pcm);
    return output.toBytes();
  }

  Future<Directory> _dir() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}neura_ambient_audio',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<MemoryCrypto> _ensureCrypto() async {
    return _crypto ??= await MemoryCrypto.demo();
  }

  Future<void> _persist(Uint8List wav, int durationMs, int generation) async {
    if (!_persistStillAllowed(generation)) return;
    final crypto = await _ensureCrypto();
    if (!_persistStillAllowed(generation)) return;
    final encrypted = await crypto.encryptBytes(wav);
    if (!_persistStillAllowed(generation)) return;

    final directory = await _dir();
    if (!_persistStillAllowed(generation)) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'amb_$timestamp.enc';
    final file = File('${directory.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(encrypted, flush: true);

    if (!_persistStillAllowed(generation)) {
      try {
        await file.delete();
      } catch (_) {}
      return;
    }

    final indexFile = File(
      '${directory.path}${Platform.pathSeparator}index.jsonl',
    );
    final line = jsonEncode({
      'filename': filename,
      'timestampMs': timestamp,
      'durationMs': durationMs,
      'sizeBytes': encrypted.length,
    });
    await indexFile.writeAsString(
      '$line\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}
