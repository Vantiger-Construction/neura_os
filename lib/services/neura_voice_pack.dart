import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:record/record.dart';

import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';

/// =========================
///  Neura Voice Pack (Offline)
/// =========================
class NeuraVoiceFrame {
  final double talkLevel;
  final double rest, aa, ee, oo, ff, mm;

  const NeuraVoiceFrame({
    required this.talkLevel,
    required this.rest,
    required this.aa,
    required this.ee,
    required this.oo,
    required this.ff,
    required this.mm,
  });

  static const idle = NeuraVoiceFrame(
    talkLevel: 0,
    rest: 0.88,
    aa: 0,
    ee: 0,
    oo: 0,
    ff: 0,
    mm: 0.12,
  );
}

class NeuraVoicePack {
  NeuraVoicePack._() {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  static final NeuraVoicePack I = NeuraVoicePack._();

  AudioPlayer? _player;
  StreamSubscription<void>? _playerCompleteSub;
  final StreamController<NeuraVoiceFrame> _out = StreamController.broadcast();
  Stream<NeuraVoiceFrame> get stream => _out.stream;

  bool _disposed = false;
  bool _initialized = false;
  bool _playing = false;
  int _clipGeneration = 0;
  NeuraEnvelope? _envelope;
  NeuraVisemeTimeline? _timeline;
  NeuraVisemeFallback? _fallback;
  DateTime? _clipStart;
  Timer? _tick;

  _VoicePackMicDriver? _mic;
  StreamSubscription<_MicFrame>? _micSub;
  Future<void>? _micStartInFlight;
  Future<void>? _micStopInFlight;
  int _micGeneration = 0;
  bool _micEnabled = false;

  bool get isPlaying => _playing;
  bool get audioAllowed => !_disposed && !SafeBoot.instance.safeMode.value;

  Future<void> init({bool enableMic = true}) async {
    if (_initialized || !audioAllowed) return;
    _ensurePlayer();
    if (enableMic) await startMic();
    if (!audioAllowed) return;
    _initialized = true;
  }

  Future<void> startMic() {
    final existing = _micStartInFlight;
    if (existing != null) return existing;
    if (_micEnabled || !audioAllowed) return Future<void>.value();

    late final Future<void> operation;
    operation = _startMicOnce().whenComplete(() {
      if (identical(_micStartInFlight, operation)) _micStartInFlight = null;
    });
    _micStartInFlight = operation;
    return operation;
  }

  Future<void> _startMicOnce() async {
    final stopping = _micStopInFlight;
    if (stopping != null) await stopping;
    if (_micEnabled || !audioAllowed) return;

    final generation = ++_micGeneration;
    final mic = _mic ??= _VoicePackMicDriver();
    StreamSubscription<_MicFrame>? newSubscription;

    try {
      final started = await mic.start();
      if (!started) return;
      if (generation != _micGeneration || !audioAllowed) {
        await mic.stop();
        return;
      }

      final subscription = mic.stream.listen(
        (frame) {
          if (generation != _micGeneration ||
              !_micEnabled ||
              !audioAllowed ||
              _playing ||
              _out.isClosed) {
            return;
          }
          _out.add(
            NeuraVoiceFrame(
              talkLevel: frame.talkLevel,
              rest: frame.rest,
              aa: frame.aa,
              ee: frame.ee,
              oo: frame.oo,
              ff: frame.ff,
              mm: frame.mm,
            ),
          );
        },
        onError: (Object error, StackTrace stack) {
          unawaited(_handleMicStreamError(error, stack));
        },
      );
      newSubscription = subscription;

      if (generation != _micGeneration || !audioAllowed) {
        await subscription.cancel();
        newSubscription = null;
        await mic.stop();
        return;
      }

      _micSub = subscription;
      newSubscription = null;
      _micEnabled = true;
    } catch (error, stack) {
      _micEnabled = false;
      try {
        await newSubscription?.cancel();
      } catch (_) {}
      try {
        await mic.stop();
      } catch (_) {}
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _handleMicStreamError(Object error, StackTrace stack) async {
    try {
      await AppLog.instance.caught(
        'voice_pack_mic_stream_failed',
        error,
        stack,
      );
    } finally {
      try {
        await stopMic();
      } catch (stopError, stopStack) {
        await AppLog.instance.caught(
          'voice_pack_mic_stop_failed',
          stopError,
          stopStack,
        );
      }
    }
  }

  Future<void> stopMic() {
    final existing = _micStopInFlight;
    if (existing != null) return existing;

    _micGeneration += 1;
    _micEnabled = false;
    late final Future<void> operation;
    operation = _stopMicOnce().whenComplete(() {
      if (identical(_micStopInFlight, operation)) _micStopInFlight = null;
    });
    _micStopInFlight = operation;
    return operation;
  }

  Future<void> _stopMicOnce() async {
    final starting = _micStartInFlight;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {}
    }

    Object? cleanupError;
    StackTrace? cleanupStack;
    final subscription = _micSub;
    _micSub = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (error, stack) {
        cleanupError = error;
        cleanupStack = stack;
      }
    }

    try {
      await _mic?.stop();
    } catch (error, stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    }

    final error = cleanupError;
    if (error != null) {
      Error.throwWithStackTrace(error, cleanupStack ?? StackTrace.current);
    }
  }

  bool _clipRequestCurrent(int generation) =>
      generation == _clipGeneration && audioAllowed;

  bool _clipPlaybackCurrent(int generation) =>
      _clipRequestCurrent(generation) && _playing;

  Future<void> playAsset(String filename) async {
    await _stopClip();
    if (!audioAllowed) return;
    final generation = _clipGeneration;

    try {
      final envelope = await NeuraEnvelopeLoader.loadFor(filename);
      if (!_clipRequestCurrent(generation)) return;

      final timeline = await NeuraVisemeTimelineLoader.loadForAudio(filename);
      if (!_clipRequestCurrent(generation)) return;

      final player = _ensurePlayer();
      await _playerCompleteSub?.cancel();
      _playerCompleteSub = null;
      if (!_clipRequestCurrent(generation)) return;

      _envelope = envelope;
      _timeline = timeline;
      _fallback = NeuraVisemeFallback();
      _clipStart = DateTime.now();
      _playing = true;

      _playerCompleteSub = player.onPlayerComplete.listen((_) {
        if (generation != _clipGeneration) return;
        unawaited(_stopClip().catchError((_) {}));
      });

      await player.play(AssetSource('audio/neura/$filename'));
      if (!_clipPlaybackCurrent(generation)) return;

      _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!_clipPlaybackCurrent(generation)) return;
        final start = _clipStart;
        if (start == null || _out.isClosed) return;

        final seconds =
            DateTime.now().difference(start).inMilliseconds / 1000.0;
        final talkLevel = _envelope?.sample(seconds) ?? 0.35;
        final timeline = _timeline;
        final weights = timeline != null
            ? timeline.sample(seconds, talkLevel: talkLevel)
            : _fallback!.tick(talkLevel: talkLevel, dt: 1 / 30);

        _out.add(
          NeuraVoiceFrame(
            talkLevel: talkLevel,
            rest: weights.rest,
            aa: weights.aa,
            ee: weights.ee,
            oo: weights.oo,
            ff: weights.ff,
            mm: weights.mm,
          ),
        );
      });
    } catch (error, stack) {
      if (generation == _clipGeneration) await _stopClip();
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> stop() async {
    await _stopClip();
    if (!_out.isClosed) _out.add(NeuraVoiceFrame.idle);
  }

  Future<void> _stopClip() async {
    _clipGeneration += 1;
    _playing = false;
    _tick?.cancel();
    _tick = null;
    _clipStart = null;
    _envelope = null;
    _timeline = null;
    _fallback = null;

    final completionSubscription = _playerCompleteSub;
    _playerCompleteSub = null;
    try {
      await completionSubscription?.cancel();
    } catch (_) {}

    final player = _player;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);

    Object? cleanupError;
    StackTrace? cleanupStack;
    try {
      await stop();
    } catch (error, stack) {
      cleanupError = error;
      cleanupStack = stack;
    }
    try {
      await stopMic();
    } catch (error, stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    }
    try {
      await _mic?.dispose();
      await _player?.dispose();
    } catch (error, stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    }
    if (!_out.isClosed) await _out.close();

    final error = cleanupError;
    if (error != null) {
      Error.throwWithStackTrace(error, cleanupStack ?? StackTrace.current);
    }
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    return _player = AudioPlayer();
  }

  void _onSafeModeChanged() {
    if (audioAllowed) return;
    unawaited(_stopForSafeMode());
  }

  Future<void> _stopForSafeMode() async {
    try {
      await stopMic();
    } catch (error, stack) {
      await AppLog.instance.caught(
        'voice_pack_safe_mode_mic_stop_failed',
        error,
        stack,
      );
    }
    try {
      await stop();
    } catch (error, stack) {
      await AppLog.instance.caught(
        'voice_pack_safe_mode_clip_stop_failed',
        error,
        stack,
      );
    }
  }
}

class NeuraEnvelope {
  final int fps;
  final List<double> levels;

  NeuraEnvelope({required this.fps, required this.levels});

  double sample(double seconds) {
    if (levels.isEmpty) return 0.0;
    final index = (seconds * fps).floor();
    if (index < 0) return levels.first;
    if (index >= levels.length) return levels.last;
    return levels[index].clamp(0.0, 1.0);
  }
}

class NeuraEnvelopeLoader {
  static Future<NeuraEnvelope?> loadFor(String audioFile) async {
    final stem = _stem(audioFile);
    final path = 'assets/audio/neura/envelopes/$stem.json';
    try {
      final raw = await rootBundle.loadString(path);
      final object = json.decode(raw) as Map<String, dynamic>;
      final fps = (object['fps'] as num?)?.toInt() ?? 30;
      final levels = (object['levels'] as List<dynamic>? ?? const [])
          .map((value) => (value as num).toDouble())
          .toList();
      return NeuraEnvelope(fps: fps, levels: levels);
    } catch (_) {
      return null;
    }
  }
}

class NeuraVisemeWeights {
  double rest = 1;
  double aa = 0;
  double ee = 0;
  double oo = 0;
  double ff = 0;
  double mm = 0;

  void normalize() {
    final total = rest + aa + ee + oo + ff + mm;
    if (total <= 1e-6) {
      rest = 1;
      aa = ee = oo = ff = mm = 0;
      return;
    }
    final scale = 1.0 / total;
    rest *= scale;
    aa *= scale;
    ee *= scale;
    oo *= scale;
    ff *= scale;
    mm *= scale;
  }

  static NeuraVisemeWeights fromMap(Map<String, dynamic> values) {
    final weights = NeuraVisemeWeights();
    double number(String key) =>
        values[key] is num ? (values[key] as num).toDouble() : 0.0;

    weights.aa = number('aa');
    weights.ee = number('ee');
    weights.oo = number('oo');
    weights.ff = number('ff');
    weights.mm = number('mm');
    weights.rest = values.containsKey('rest')
        ? number('rest')
        : (1.0 -
                  (weights.aa +
                      weights.ee +
                      weights.oo +
                      weights.ff +
                      weights.mm))
              .clamp(0.0, 1.0);
    weights.normalize();
    return weights;
  }
}

class NeuraVisemeTimeline {
  final int fps;
  final List<NeuraVisemeWeights> frames;

  NeuraVisemeTimeline({required this.fps, required this.frames});

  NeuraVisemeWeights _frameAt(double seconds) {
    if (frames.isEmpty) return NeuraVisemeWeights();
    final index = (seconds * fps).floor();
    if (index <= 0) return frames.first;
    if (index >= frames.length - 1) return frames.last;
    return frames[index];
  }

  NeuraVisemeWeights sample(double seconds, {required double talkLevel}) {
    final frame = _frameAt(seconds);
    final base = NeuraVisemeWeights.fromMap({
      'rest': frame.rest,
      'aa': frame.aa,
      'ee': frame.ee,
      'oo': frame.oo,
      'ff': frame.ff,
      'mm': frame.mm,
    });

    final level = talkLevel.clamp(0.0, 1.0);
    base.aa *= 0.35 + 0.65 * level;
    base.ee *= 0.35 + 0.65 * level;
    base.oo *= 0.35 + 0.65 * level;
    base.ff *= 0.50 + 0.50 * level;
    base.mm *= 0.70 + 0.30 * (1.0 - level);
    base.rest = (1.0 - (base.aa + base.ee + base.oo + base.ff + base.mm)).clamp(
      0.0,
      1.0,
    );
    base.normalize();
    return base;
  }

  static NeuraVisemeTimeline fromFramesJson(Map<String, dynamic> object) {
    final fps = (object['fps'] as num?)?.toInt() ?? 30;
    final list = object['frames'] as List<dynamic>? ?? const [];
    final frames = list
        .map(
          (value) => NeuraVisemeWeights.fromMap(value as Map<String, dynamic>),
        )
        .toList(growable: false);
    return NeuraVisemeTimeline(fps: fps, frames: frames);
  }
}

class NeuraVisemeTimelineLoader {
  static Future<NeuraVisemeTimeline?> loadForAudio(String audioFile) async {
    final stem = _stem(audioFile);
    final path = 'assets/audio/neura/visemes/$stem.json';
    try {
      final raw = await rootBundle.loadString(path);
      final object = json.decode(raw) as Map<String, dynamic>;
      if (!object.containsKey('frames')) return null;
      return NeuraVisemeTimeline.fromFramesJson(object);
    } catch (_) {
      return null;
    }
  }
}

class NeuraVisemeFallback {
  double _phase = 0;
  final NeuraVisemeWeights _weights = NeuraVisemeWeights();

  NeuraVisemeWeights tick({required double talkLevel, required double dt}) {
    final level = talkLevel.clamp(0.0, 1.0);
    if (level < 0.03) {
      _weights.mm = _lerp(_weights.mm, 0.10, dt);
      _weights.aa = _lerp(_weights.aa, 0.00, dt);
      _weights.ee = _lerp(_weights.ee, 0.00, dt);
      _weights.oo = _lerp(_weights.oo, 0.00, dt);
      _weights.ff = _lerp(_weights.ff, 0.00, dt);
      _weights.rest = _lerp(_weights.rest, 0.90, dt);
      _weights.normalize();
      return _weights;
    }

    _phase += dt * (3.0 + 10.0 * level);
    final aMix = 0.5 + 0.5 * math.sin(_phase);
    final eMix = 0.5 + 0.5 * math.sin(_phase * 1.37 + 1.2);
    final oMix = 0.5 + 0.5 * math.sin(_phase * 0.82 + 2.4);
    final mmPulse = 0.5 + 0.5 * math.sin(_phase * 2.7 + 0.7);
    final ffPulse = 0.5 + 0.5 * math.sin(_phase * 3.1 + 2.1);

    final open = (level * 0.95 + 0.05).clamp(0.0, 1.0);
    final targetMm = (0.10 + 0.25 * mmPulse * (1.0 - level)).clamp(0.0, 0.35);
    final targetFf = (0.05 + 0.25 * ffPulse).clamp(0.0, 0.30);
    final vowelEnergy = (open * (1.0 - targetMm)).clamp(0.0, 1.0);
    final sum = (aMix + eMix + oMix).clamp(0.001, 3.0);
    final targetAa = vowelEnergy * (aMix / sum) * 1.10;
    final targetEe = vowelEnergy * (eMix / sum);
    final targetOo = vowelEnergy * (oMix / sum) * 1.05;
    final targetRest =
        (1.0 - (targetAa + targetEe + targetOo + targetFf + targetMm)).clamp(
          0.0,
          1.0,
        );

    _weights.mm = _lerp(_weights.mm, targetMm, dt);
    _weights.ff = _lerp(_weights.ff, targetFf, dt);
    _weights.aa = _lerp(_weights.aa, targetAa, dt);
    _weights.ee = _lerp(_weights.ee, targetEe, dt);
    _weights.oo = _lerp(_weights.oo, targetOo, dt);
    _weights.rest = _lerp(_weights.rest, targetRest, dt);
    _weights.normalize();
    return _weights;
  }

  double _lerp(double from, double to, double dt) {
    final scale = (10.0 * dt).clamp(0.0, 1.0);
    return from + (to - from) * scale;
  }
}

class _MicFrame {
  final double talkLevel;
  final double rest, aa, ee, oo, ff, mm;

  const _MicFrame(
    this.talkLevel,
    this.rest,
    this.aa,
    this.ee,
    this.oo,
    this.ff,
    this.mm,
  );
}

class NeuraMicVisemeEngine {
  final int sampleRate;
  final int analysisHz;
  final double noiseZcrThresh;
  final double gate;
  final double smooth;
  final double mmAttack;

  NeuraMicVisemeEngine({
    this.sampleRate = 16000,
    this.analysisHz = 30,
    this.noiseZcrThresh = 0.16,
    this.gate = 0.02,
    this.smooth = 0.25,
    this.mmAttack = 0.55,
  });

  double _rmsSmoothed = 0;
  double _zcrSmoothed = 0;
  double _talkSmoothed = 0;
  double _previousRms = 0;

  _MicFrame processPcm16(Int16List pcm) {
    double sumSquares = 0;
    var zeroCrossings = 0;
    var previousSign = 0;

    for (var index = 0; index < pcm.length; index++) {
      final sample = pcm[index];
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
      final sign = sample >= 0 ? 1 : -1;
      if (index > 0 && sign != previousSign) zeroCrossings += 1;
      previousSign = sign;
    }

    final rms = math.sqrt(sumSquares / math.max(1, pcm.length));
    final zcr = zeroCrossings / math.max(1, pcm.length).toDouble();
    _rmsSmoothed = _lerp(_rmsSmoothed, rms, smooth);
    _zcrSmoothed = _lerp(_zcrSmoothed, zcr, smooth);

    final gated = ((_rmsSmoothed - gate) / 0.22).clamp(0.0, 1.0);
    _talkSmoothed = _lerp(_talkSmoothed, gated, smooth);
    final attack = ((_rmsSmoothed - _previousRms) * 6.0).clamp(0.0, 1.0);
    _previousRms = _rmsSmoothed;
    final fricative = ((_zcrSmoothed - noiseZcrThresh) / 0.20).clamp(0.0, 1.0);

    if (_talkSmoothed < 0.05) {
      const mm = 0.12;
      return const _MicFrame(0.0, 1.0 - mm, 0, 0, 0, 0, mm);
    }

    final vowelEnergy = (_talkSmoothed * (1.0 - fricative * 0.55)).clamp(
      0.0,
      1.0,
    );
    final seconds = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final aMix = (0.5 + 0.5 * math.sin(seconds * 6.0)).clamp(0.0, 1.0);
    final eMix = (0.5 + 0.5 * math.sin(seconds * 7.3 + 1.1)).clamp(0.0, 1.0);
    final oMix = (0.5 + 0.5 * math.sin(seconds * 5.1 + 2.2)).clamp(0.0, 1.0);
    final sum = (aMix + eMix + oMix).clamp(0.001, 3.0);

    var aa = vowelEnergy * (aMix / sum) * 1.10;
    var ee = vowelEnergy * (eMix / sum);
    var oo = vowelEnergy * (oMix / sum) * 1.05;
    var ff = (_talkSmoothed * (0.15 + 0.85 * fricative)).clamp(0.0, 0.55);
    var mm = (attack * mmAttack).clamp(0.0, 0.65);
    var rest = (1.0 - (aa + ee + oo + ff + mm)).clamp(0.0, 1.0);

    final total = rest + aa + ee + oo + ff + mm;
    if (total > 1e-6) {
      final scale = 1.0 / total;
      rest *= scale;
      aa *= scale;
      ee *= scale;
      oo *= scale;
      ff *= scale;
      mm *= scale;
    }

    return _MicFrame(_talkSmoothed, rest, aa, ee, oo, ff, mm);
  }

  double _lerp(double from, double to, double amount) =>
      from + (to - from) * amount;
}

class _VoicePackMicDriver {
  final NeuraMicVisemeEngine engine;
  final StreamController<_MicFrame> _out = StreamController.broadcast();
  Stream<_MicFrame> get stream => _out.stream;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;

  _VoicePackMicDriver({NeuraMicVisemeEngine? engine})
    : engine = engine ?? NeuraMicVisemeEngine();

  Future<bool> start() async {
    if (_audioSub != null) return true;
    if (!await _recorder.hasPermission()) return false;

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _audioSub = audioStream.listen(
      (bytes) {
        if (_out.isClosed) return;
        final pcm = Int16List.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes ~/ 2,
        );
        _out.add(engine.processPcm16(pcm));
      },
      onError: (Object error, StackTrace stack) {
        if (!_out.isClosed) _out.addError(error, stack);
      },
    );
    return true;
  }

  Future<void> stop() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    if (!_out.isClosed) await _out.close();
  }
}

String _stem(String filename) {
  var stem = filename;
  final dot = stem.lastIndexOf('.');
  if (dot != -1) stem = stem.substring(0, dot);
  return stem;
}
