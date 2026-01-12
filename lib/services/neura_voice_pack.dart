import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

/// =========================
///  Neura Voice Pack (Offline)
/// =========================
///
/// Features:
/// - Play bundled WAV assets (assets/audio/neura/*.wav)
/// - Emit talkLevel (0..1) from a precomputed envelope JSON if present
/// - Optional viseme timeline JSON sampling (assets/audio/neura/visemes/<stem>.json)
/// - Live mic visemes (RMS + ZCR) when no clip is playing
///
/// This is designed to be used by your Rive avatar driver:
/// subscribe to [NeuraVoicePack.I.stream] and push values into Rive inputs.

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
      talkLevel: 0, rest: 0.88, aa: 0, ee: 0, oo: 0, ff: 0, mm: 0.12);
}

class NeuraVoicePack {
  NeuraVoicePack._();
  static final NeuraVoicePack I = NeuraVoicePack._();

  final AudioPlayer _player = AudioPlayer();
  final StreamController<NeuraVoiceFrame> _out = StreamController.broadcast();
  Stream<NeuraVoiceFrame> get stream => _out.stream;

  bool _playing = false;
  bool get isPlaying => _playing;

  NeuraEnvelope? _envelope;
  NeuraVisemeTimeline? _timeline;
  DateTime? _clipStart;
  Timer? _tick;

  // Mic
  final NeuraMicDriver _mic = NeuraMicDriver();
  StreamSubscription? _micSub;
  bool _micEnabled = false;

  Future<void> init({bool enableMic = true}) async {
    // Clip complete handler
    _player.onPlayerComplete.listen((_) {
      _stopClip();
    });

    if (enableMic) {
      await startMic();
    }
  }

  Future<void> startMic() async {
    if (_micEnabled) return;
    _micEnabled = true;
    await _mic.start();
    _micSub = _mic.stream.listen((f) {
      // Mic only drives when no clip is playing
      if (_playing) return;
      _out.add(NeuraVoiceFrame(
        talkLevel: f.talkLevel,
        rest: f.rest,
        aa: f.aa,
        ee: f.ee,
        oo: f.oo,
        ff: f.ff,
        mm: f.mm,
      ));
    });
  }

  Future<void> stopMic() async {
    _micEnabled = false;
    await _micSub?.cancel();
    _micSub = null;
    await _mic.stop();
  }

  Future<void> playAsset(String filename) async {
    // filename is the WAV name inside assets/audio/neura/
    await _stopClip();

    _playing = true;
    _clipStart = DateTime.now();

    // Load envelope if exists
    _envelope = await NeuraEnvelopeLoader.loadFor(filename);

    // Load viseme timeline if exists
    _timeline = await NeuraVisemeTimelineLoader.loadForAudio(filename);

    await _player.play(AssetSource('audio/neura/$filename'));

    // Emit frames at ~30 fps
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final start = _clipStart;
      if (!_playing || start == null) return;

      final tSec = DateTime.now().difference(start).inMilliseconds / 1000.0;
      final talk = _envelope?.sample(tSec) ?? 0.35;

      final w = (_timeline != null)
          ? _timeline!.sample(tSec, talkLevel: talk)
          : NeuraVisemeFallback().tick(talkLevel: talk, dt: 1 / 30);

      _out.add(NeuraVoiceFrame(
        talkLevel: talk,
        rest: w.rest,
        aa: w.aa,
        ee: w.ee,
        oo: w.oo,
        ff: w.ff,
        mm: w.mm,
      ));
    });
  }

  Future<void> stop() async {
    await _stopClip();
    _out.add(NeuraVoiceFrame.idle);
  }

  Future<void> dispose() async {
    await stop();
    await stopMic();
    await _player.dispose();
    await _out.close();
  }

  Future<void> _stopClip() async {
    _playing = false;
    _tick?.cancel();
    _tick = null;
    _clipStart = null;
    _envelope = null;
    _timeline = null;
    try {
      await _player.stop();
    } catch (_) {}
  }
}

/// =========================
/// Envelope (talkLevel over time)
/// =========================
class NeuraEnvelope {
  final int fps;
  final List<double> levels;
  NeuraEnvelope({required this.fps, required this.levels});

  double sample(double tSec) {
    if (levels.isEmpty) return 0.0;
    final i = (tSec * fps).floor();
    if (i < 0) return levels.first;
    if (i >= levels.length) return levels.last;
    return levels[i].clamp(0.0, 1.0);
  }
}

class NeuraEnvelopeLoader {
  static Future<NeuraEnvelope?> loadFor(String audioFile) async {
    final stem = _stem(audioFile);
    final path = 'assets/audio/neura/envelopes/$stem.json';
    try {
      final s = await rootBundle.loadString(path);
      final obj = json.decode(s) as Map<String, dynamic>;
      final fps = (obj['fps'] as num?)?.toInt() ?? 30;
      final levels = (obj['levels'] as List<dynamic>? ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      return NeuraEnvelope(fps: fps, levels: levels);
    } catch (_) {
      return null;
    }
  }
}

/// =========================
/// Viseme Timeline (optional)
/// =========================
class NeuraVisemeWeights {
  double rest = 1, aa = 0, ee = 0, oo = 0, ff = 0, mm = 0;

  void normalize() {
    final s = rest + aa + ee + oo + ff + mm;
    if (s <= 1e-6) {
      rest = 1;
      aa = ee = oo = ff = mm = 0;
      return;
    }
    final k = 1.0 / s;
    rest *= k;
    aa *= k;
    ee *= k;
    oo *= k;
    ff *= k;
    mm *= k;
  }

  static NeuraVisemeWeights fromMap(Map<String, dynamic> m) {
    final w = NeuraVisemeWeights();
    double numv(String k) => (m[k] is num) ? (m[k] as num).toDouble() : 0.0;
    w.aa = numv('aa');
    w.ee = numv('ee');
    w.oo = numv('oo');
    w.ff = numv('ff');
    w.mm = numv('mm');
    w.rest = (m.containsKey('rest'))
        ? numv('rest')
        : (1.0 - (w.aa + w.ee + w.oo + w.ff + w.mm)).clamp(0.0, 1.0);
    w.normalize();
    return w;
  }
}

class NeuraVisemeTimeline {
  final int fps;
  final List<NeuraVisemeWeights> frames;
  NeuraVisemeTimeline({required this.fps, required this.frames});

  NeuraVisemeWeights _frameAt(double tSec) {
    if (frames.isEmpty) return NeuraVisemeWeights();
    final i = (tSec * fps).floor();
    if (i <= 0) return frames.first;
    if (i >= frames.length - 1) return frames.last;
    return frames[i];
  }

  NeuraVisemeWeights sample(double tSec, {required double talkLevel}) {
    final base = NeuraVisemeWeights.fromMap({
      'rest': _frameAt(tSec).rest,
      'aa': _frameAt(tSec).aa,
      'ee': _frameAt(tSec).ee,
      'oo': _frameAt(tSec).oo,
      'ff': _frameAt(tSec).ff,
      'mm': _frameAt(tSec).mm,
    });

    final t = talkLevel.clamp(0.0, 1.0);
    base.aa *= (0.35 + 0.65 * t);
    base.ee *= (0.35 + 0.65 * t);
    base.oo *= (0.35 + 0.65 * t);
    base.ff *= (0.50 + 0.50 * t);
    base.mm *= (0.70 + 0.30 * (1.0 - t));
    base.rest = (1.0 - (base.aa + base.ee + base.oo + base.ff + base.mm))
        .clamp(0.0, 1.0);
    base.normalize();
    return base;
  }

  static NeuraVisemeTimeline fromFramesJson(Map<String, dynamic> obj) {
    final fps = (obj['fps'] as num?)?.toInt() ?? 30;
    final list = (obj['frames'] as List<dynamic>? ?? const []);
    final frames = list
        .map((e) => NeuraVisemeWeights.fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
    return NeuraVisemeTimeline(fps: fps, frames: frames);
  }
}

class NeuraVisemeTimelineLoader {
  static Future<NeuraVisemeTimeline?> loadForAudio(String audioFile) async {
    final stem = _stem(audioFile);
    final path = 'assets/audio/neura/visemes/$stem.json';
    try {
      final s = await rootBundle.loadString(path);
      final obj = json.decode(s) as Map<String, dynamic>;
      if (obj.containsKey('frames'))
        return NeuraVisemeTimeline.fromFramesJson(obj);
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// =========================
/// Fallback Visemes (no timeline)
/// =========================
class NeuraVisemeFallback {
  double _phase = 0;
  NeuraVisemeWeights _w = NeuraVisemeWeights();

  NeuraVisemeWeights tick({required double talkLevel, required double dt}) {
    final t = talkLevel.clamp(0.0, 1.0);
    if (t < 0.03) {
      _w.mm = _lerp(_w.mm, 0.10, dt);
      _w.aa = _lerp(_w.aa, 0.00, dt);
      _w.ee = _lerp(_w.ee, 0.00, dt);
      _w.oo = _lerp(_w.oo, 0.00, dt);
      _w.ff = _lerp(_w.ff, 0.00, dt);
      _w.rest = _lerp(_w.rest, 0.90, dt);
      _w.normalize();
      return _w;
    }

    _phase += dt * (3.0 + 10.0 * t);
    final vA = 0.5 + 0.5 * math.sin(_phase * 1.00);
    final vE = 0.5 + 0.5 * math.sin(_phase * 1.37 + 1.2);
    final vO = 0.5 + 0.5 * math.sin(_phase * 0.82 + 2.4);
    final mmPulse = 0.5 + 0.5 * math.sin(_phase * 2.7 + 0.7);
    final ffPulse = 0.5 + 0.5 * math.sin(_phase * 3.1 + 2.1);

    final open = (t * 0.95 + 0.05).clamp(0.0, 1.0);
    final targetMm = (0.10 + 0.25 * mmPulse * (1.0 - t)).clamp(0.0, 0.35);
    final targetFf = (0.05 + 0.25 * ffPulse).clamp(0.0, 0.30);

    final vowelEnergy = (open * (1.0 - targetMm)).clamp(0.0, 1.0);
    final sumV = (vA + vE + vO).clamp(0.001, 3.0);

    final targetAa = vowelEnergy * (vA / sumV) * 1.10;
    final targetEe = vowelEnergy * (vE / sumV) * 1.00;
    final targetOo = vowelEnergy * (vO / sumV) * 1.05;

    final targetRest =
        (1.0 - (targetAa + targetEe + targetOo + targetFf + targetMm))
            .clamp(0.0, 1.0);

    _w.mm = _lerp(_w.mm, targetMm, dt);
    _w.ff = _lerp(_w.ff, targetFf, dt);
    _w.aa = _lerp(_w.aa, targetAa, dt);
    _w.ee = _lerp(_w.ee, targetEe, dt);
    _w.oo = _lerp(_w.oo, targetOo, dt);
    _w.rest = _lerp(_w.rest, targetRest, dt);

    _w.normalize();
    return _w;
  }

  double _lerp(double a, double b, double dt) {
    final k = (10.0 * dt).clamp(0.0, 1.0);
    return a + (b - a) * k;
  }
}

/// =========================
/// Live Mic Visemes
/// =========================
class _MicFrame {
  final double talkLevel;
  final double rest, aa, ee, oo, ff, mm;
  const _MicFrame(
      this.talkLevel, this.rest, this.aa, this.ee, this.oo, this.ff, this.mm);
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

  double _rmsSm = 0;
  double _zcrSm = 0;
  double _talkSm = 0;
  double _prevRms = 0;

  _MicFrame processPcm16(Int16List pcm) {
    double sumSq = 0;
    int zc = 0;
    int prev = 0;

    for (int i = 0; i < pcm.length; i++) {
      final s = pcm[i];
      final f = s / 32768.0;
      sumSq += f * f;
      final sign = s >= 0 ? 1 : -1;
      if (i > 0 && sign != prev) zc++;
      prev = sign;
    }

    final rms = math.sqrt(sumSq / math.max(1, pcm.length));
    final zcr = zc / math.max(1, pcm.length).toDouble();

    _rmsSm = _lerp(_rmsSm, rms, smooth);
    _zcrSm = _lerp(_zcrSm, zcr, smooth);

    final gated = ((_rmsSm - gate) / (0.22)).clamp(0.0, 1.0);
    _talkSm = _lerp(_talkSm, gated, smooth);

    final attack = ((_rmsSm - _prevRms) * 6.0).clamp(0.0, 1.0);
    _prevRms = _rmsSm;

    final fric = ((_zcrSm - noiseZcrThresh) / 0.20).clamp(0.0, 1.0);

    if (_talkSm < 0.05) {
      final mm = 0.12;
      final rest = 1.0 - mm;
      return _MicFrame(0.0, rest, 0, 0, 0, 0, mm);
    }

    final vowelEnergy = (_talkSm * (1.0 - fric * 0.55)).clamp(0.0, 1.0);

    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final aMix = (0.5 + 0.5 * math.sin(t * 6.0)).clamp(0.0, 1.0);
    final eMix = (0.5 + 0.5 * math.sin(t * 7.3 + 1.1)).clamp(0.0, 1.0);
    final oMix = (0.5 + 0.5 * math.sin(t * 5.1 + 2.2)).clamp(0.0, 1.0);
    final sum = (aMix + eMix + oMix).clamp(0.001, 3.0);

    double aa = vowelEnergy * (aMix / sum) * 1.10;
    double ee = vowelEnergy * (eMix / sum) * 1.00;
    double oo = vowelEnergy * (oMix / sum) * 1.05;

    double ff = (_talkSm * (0.15 + 0.85 * fric)).clamp(0.0, 0.55);
    double mm = (attack * mmAttack).clamp(0.0, 0.65);

    double rest = (1.0 - (aa + ee + oo + ff + mm)).clamp(0.0, 1.0);

    final s2 = rest + aa + ee + oo + ff + mm;
    if (s2 > 1e-6) {
      final k = 1.0 / s2;
      rest *= k;
      aa *= k;
      ee *= k;
      oo *= k;
      ff *= k;
      mm *= k;
    }

    return _MicFrame(_talkSm, rest, aa, ee, oo, ff, mm);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class NeuraMicDriver {
  FlutterSoundRecorder? _rec;
  final NeuraMicVisemeEngine engine;

  final StreamController<_MicFrame> _out = StreamController.broadcast();
  Stream<_MicFrame> get stream => _out.stream;

  final StreamController<Uint8List> _pcmController =
      StreamController<Uint8List>();

  bool _running = false;

  NeuraMicDriver({NeuraMicVisemeEngine? engine})
      : engine = engine ?? NeuraMicVisemeEngine();

  Future<void> start() async {
    if (_running) return;

    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      throw Exception('Microphone permission denied.');
    }

    _rec ??= FlutterSoundRecorder();

    await _rec!.openRecorder();
    await _rec!.setSubscriptionDuration(
        Duration(milliseconds: (1000 / engine.analysisHz).round()));

    await _rec!.startRecorder(
      toStream: _pcmController.sink,
      codec: Codec.pcm16,
      sampleRate: engine.sampleRate,
      numChannels: 1,
      bitRate: engine.sampleRate * 16,
    );

    _pcmController.stream.listen(_pcmSink);

    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    await _rec!.stopRecorder();
    await _rec!.closeRecorder();
    _running = false;
  }

  void dispose() {
    _out.close();
    _pcmController.close();
  }

  void _pcmSink(Uint8List data) {
    final bytes = data;

    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    final pcm = Int16List(n);
    for (int i = 0; i < n; i++) {
      pcm[i] = bd.getInt16(i * 2, Endian.little);
    }

    final frame = engine.processPcm16(pcm);
    _out.add(frame);
  }
}

String _stem(String filename) {
  var s = filename;
  final dot = s.lastIndexOf('.');
  if (dot != -1) s = s.substring(0, dot);
  return s;
}
