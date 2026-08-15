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

/// Whether [AmbientListeningService.greetAndStartListening] actually speaks
/// its greeting at boot.
///
/// Disabled by default as of this build. Root cause: the app's first
/// proactive (non-user-initiated) native TTS call, happening a couple
/// seconds after launch while the floating mascot window's own separate
/// engine process is also spinning up, crashes the whole process with an
/// access violation in flutter_tts_plugin.dll (0xC0000005) -- confirmed via
/// repeated crash reproduction and Windows Error Reporting during beta
/// testing. Two mitigation attempts (warming the TTS engine up earlier in
/// boot -- see NeuraStartupCoordinator's TtsWarmup step, still kept, it's
/// harmless -- and adding a grace period after the mascot window's creation
/// future resolves) both measurably reduced but did not reliably eliminate
/// the crash across repeated test launches. Given a native access violation
/// can't be caught by Dart exception handling (it kills the process
/// outright, not just the call), skipping the call entirely is the only
/// mitigation that has actually been confirmed crash-free. All other
/// TTS usage (chat replies, wake-word replies, Voice Lab) is user-initiated,
/// happens well after boot with no mascot-window race, and is unaffected.
///
/// Flip this back to true once the underlying flutter_tts/mascot-window
/// race is properly root-caused and fixed -- this is a mitigation, not a
/// permanent feature removal.
const bool kEnableProactiveGreetingTts = false;

/// Voice-activity-triggered ambient recording, encrypted at rest.
///
/// Deliberately NOT indiscriminate always-on capture: the mic stream is
/// only ever open while [AmbientListeningPrefsController.enabled] is true
/// (opt-in, off by default), and a clip is only saved for the span between
/// detected speech-start and a short silence debounce afterward -- silence
/// itself is never captured or written to disk.
///
/// [isLive] is the single source of truth for the persistent "mic is
/// recording right now" indicator (see AmbientRecordingBadge) -- it is
/// `true` only during an actual VAD-triggered capture window, never merely
/// because the underlying stream is open and listening for the next
/// utterance.
class AmbientListeningService {
  AmbientListeningService._() {
    // Live-reacts to the Settings toggle, not just the value read once at
    // boot -- flipping it off mid-conversation must stop capture
    // immediately (the one-tap pause requirement), and flipping it on
    // should start listening right away without needing an app restart.
    AmbientListeningPrefsController.instance.enabled.addListener(_onPrefChanged);
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }
  static final AmbientListeningService instance = AmbientListeningService._();

  bool get captureAllowed => !SafeBoot.instance.safeMode.value;

  void _onPrefChanged() {
    if (!captureAllowed) {
      if (_running) unawaited(stop());
      return;
    }
    final enabled = AmbientListeningPrefsController.instance.enabled.value;
    if (enabled && !_running) {
      unawaited(start());
    } else if (!enabled && _running) {
      unawaited(stop());
    }
  }

  void _onSafeModeChanged() {
    if (!captureAllowed && _running) unawaited(stop());
  }

  /// Same threshold/normalization NeuraMicDriver already uses -- don't
  /// reinvent the VAD gate.
  static const double _kListenThreshold = 0.12;
  static const double _kFloor = -50.0;

  static const Duration _kPollInterval = Duration(milliseconds: 80);
  static const Duration _kPreRoll = Duration(milliseconds: 700);
  static const Duration _kPostRollSilence = Duration(milliseconds: 800);
  static const Duration _kMinUtterance = Duration(milliseconds: 400);
  static const Duration _kMaxUtterance = Duration(minutes: 2);

  static const int _sampleRate = 16000;
  static const int _bytesPerSample = 2; // pcm16bits, mono

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _amplitudeTimer;
  Timer? _silenceTimer;

  bool _running = false;
  bool _capturing = false;

  final Queue<Uint8List> _preRollBuffer = Queue<Uint8List>();
  int _preRollBytes = 0;
  final BytesBuilder _utteranceBuffer = BytesBuilder(copy: false);
  int _utteranceStartMs = 0;

  MemoryCrypto? _crypto;
  Future<void> _persistQueue = Future<void>.value();
  int _dataGeneration = 0;

  final ValueNotifier<bool> isLive = ValueNotifier<bool>(false);

  int get _preRollCapBytes =>
      (_kPreRoll.inMilliseconds / 1000 * _sampleRate * _bytesPerSample)
          .round();

  /// Speaks a short greeting, then -- only if the user has opted in via
  /// Settings -- starts ambient listening. Greeting happens first so
  /// Neura's own voice through the speakers doesn't immediately trip her
  /// own voice-activity gate.
  Future<void> greetAndStartListening() async {
    if (!captureAllowed) return;
    // Wait for the mascot window's own native engine/window creation to
    // settle first. Confirmed via crash reproduction (Windows Error
    // Reporting: flutter_tts_plugin.dll, exception 0xC0000005) that firing
    // this app's first proactive TTS call while that second engine is still
    // spinning up crashes the process outright -- a plain delay isn't
    // enough to avoid this since the mascot window's own creation time
    // varies. See MascotWindowService.initialCreationSettled.
    await MascotWindowService.I.initialCreationSettled;
    if (!captureAllowed) return;

    // The spoken greeting is disabled by default (see
    // kEnableProactiveGreetingTts doc comment) -- everything else in this
    // method (opt-in ambient listening) still runs normally.
    if (kEnableProactiveGreetingTts) {
      try {
        // Hard timeout: if flutter_tts's native Windows voice-init/enumeration
        // path ever blocks the platform thread on a given machine, waiting on
        // it unbounded here would leave the whole app appearing to hang right
        // as the dashboard tries to render. Giving up after a few seconds
        // means a slow/broken TTS backend degrades to "no spoken greeting"
        // instead of "app never loads."
        await NeuraTtsService.instance
            .speak("Hi. I'm Neura. I'm here if you need me.")
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        await AppLog.instance.warn('ambient_greet_failed: $e');
      }
    }

    if (AmbientListeningPrefsController.instance.enabled.value) {
      await start();
    }
  }

  Future<void> start() async {
    if (_running || !captureAllowed) return;
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      await AppLog.instance.warn('ambient_listening_no_mic_permission');
      return;
    }
    if (!captureAllowed) return;

    try {
      final audioStream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      _audioSub = audioStream.listen(_onAudioChunk);
      if (!captureAllowed) {
        await stop();
        return;
      }
    } catch (e) {
      await AppLog.instance.warn('ambient_listening_start_failed: $e');
      return;
    }

    _running = true;
    _amplitudeTimer = Timer.periodic(_kPollInterval, (_) => _pollAmplitude());
  }

  Future<void> stop() async {
    _running = false;
    _capturing = false;
    isLive.value = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    _preRollBuffer.clear();
    _preRollBytes = 0;
    _utteranceBuffer.clear();
    try {
      await _recorder?.stop();
    } catch (_) {}
  }

  /// Stops every producer and releases the cached data-encryption handle
  /// before on-disk recordings and the device key are removed.
  Future<void> resetAfterDataWipe() async {
    _dataGeneration += 1;
    await stop();
    await _persistQueue;
    _crypto = null;
  }

  void _onAudioChunk(Uint8List chunk) {
    if (_capturing) {
      _utteranceBuffer.add(chunk);
      // Force-finalize runaway continuous noise rather than growing one
      // file unboundedly.
      final elapsedMs =
          DateTime.now().millisecondsSinceEpoch - _utteranceStartMs;
      if (elapsedMs >= _kMaxUtterance.inMilliseconds) {
        unawaited(_finalizeUtterance());
      }
    } else {
      _preRollBuffer.add(chunk);
      _preRollBytes += chunk.length;
      while (_preRollBytes > _preRollCapBytes && _preRollBuffer.isNotEmpty) {
        _preRollBytes -= _preRollBuffer.removeFirst().length;
      }
    }
  }

  Future<void> _pollAmplitude() async {
    if (!_running) return;
    if (!captureAllowed) {
      await stop();
      return;
    }
    double normalized;
    try {
      final recorder = _recorder;
      if (recorder == null) return;
      final amp = await recorder.getAmplitude();
      normalized = ((amp.current - _kFloor) / (-_kFloor)).clamp(0.0, 1.0);
    } catch (_) {
      normalized = 0.0;
    }

    final aboveThreshold = normalized > _kListenThreshold;

    if (aboveThreshold) {
      _silenceTimer?.cancel();
      _silenceTimer = Timer(_kPostRollSilence, () {
        unawaited(_finalizeUtterance());
      });

      if (!_capturing) {
        _capturing = true;
        isLive.value = true;
        _utteranceStartMs = DateTime.now().millisecondsSinceEpoch;
        _utteranceBuffer.clear();
        // Drain pre-roll into the utterance so the first syllable isn't
        // clipped.
        for (final chunk in _preRollBuffer) {
          _utteranceBuffer.add(chunk);
        }
        _preRollBuffer.clear();
        _preRollBytes = 0;
      }
    }
  }

  Future<void> _finalizeUtterance() async {
    if (!_capturing || !captureAllowed) return;
    _capturing = false;
    isLive.value = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;

    final pcm = _utteranceBuffer.takeBytes();
    final durationMs =
        (pcm.length / _bytesPerSample / _sampleRate * 1000).round();

    if (durationMs < _kMinUtterance.inMilliseconds) {
      // Too short to be real speech -- a click, a bump. Discard silently.
      return;
    }

    final generation = _dataGeneration;
    try {
      final wav = _wrapWav(pcm);
      final next = _persistQueue.then((_) async {
        if (generation != _dataGeneration || !captureAllowed) return;
        await _persist(wav, durationMs);
      });
      _persistQueue = next.then<void>((_) {}, onError: (_) {});
      await next;
    } catch (e) {
      await AppLog.instance.warn('ambient_listening_persist_failed: $e');
    }
  }

  Uint8List _wrapWav(Uint8List pcm) {
    const bitsPerSample = 16;
    const channels = 1;
    final byteRate = _sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    final header = ByteData(44);
    void writeString(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat = PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeString(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);

    final out = BytesBuilder(copy: false);
    out.add(header.buffer.asUint8List());
    out.add(pcm);
    return out.toBytes();
  }

  Future<Directory> _dir() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}neura_ambient_audio');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<MemoryCrypto> _ensureCrypto() async {
    return _crypto ??= await MemoryCrypto.demo();
  }

  Future<void> _persist(Uint8List wav, int durationMs) async {
    if (!captureAllowed) return;
    final crypto = await _ensureCrypto();
    if (!captureAllowed) return;
    final encrypted = await crypto.encryptBytes(wav);

    final dir = await _dir();
    if (!captureAllowed) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final filename = 'amb_$ts.enc';
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(encrypted, flush: true);

    final indexFile =
        File('${dir.path}${Platform.pathSeparator}index.jsonl');
    final line = jsonEncode({
      'filename': filename,
      'timestampMs': ts,
      'durationMs': durationMs,
      'sizeBytes': encrypted.length,
    });
    await indexFile.writeAsString('$line\n',
        mode: FileMode.append, flush: true);
  }
}
