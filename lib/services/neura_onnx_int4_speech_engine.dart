import 'dart:async';

import 'package:flutter/services.dart';

import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';
import 'neura_speech_engine.dart';

/// Experimental native seam for operator-supplied ONNX streaming ASR.
///
/// No model is bundled and no implementation is assumed. The adapter becomes
/// selectable only when a platform runner implements the channel and reports
/// availability. This keeps benchmark code provider-neutral without silently
/// changing the production recognizer.
/// The historical int4 identifier is not a claim about model quantization;
/// the Windows prototype also accepts an explicitly selected int8 profile.
final class NeuraOnnxInt4SpeechEngine implements NeuraSpeechEngine {
  NeuraOnnxInt4SpeechEngine({
    MethodChannel channel = const MethodChannel('neura/on_device_asr'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handleCall);
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  final MethodChannel _channel;
  final StreamController<NeuraSpeechSegment> _segments =
      StreamController<NeuraSpeechSegment>.broadcast();
  bool _listening = false;
  bool _starting = false;
  bool _nativeStartPending = false;
  bool _disposed = false;
  Future<String>? _stopping;
  Completer<void>? _startSettled;
  int _startGeneration = 0;

  @override
  String get id => 'onnx_int4_experimental';

  @override
  NeuraSpeechEngineCapabilities get capabilities =>
      const NeuraSpeechEngineCapabilities(
        onDevice: true,
        supportsPartialResults: true,
        // The first Windows runner emits transcript segments and endpoint
        // state only. Do not invent a confidence value that the selected
        // streaming transducer does not expose.
        supportsConfidence: false,
        supportedPlatforms: {'windows', 'android'},
        experimental: true,
      );

  @override
  Stream<NeuraSpeechSegment> get segments => _segments.stream;

  @override
  bool get isListening => _listening;

  bool get listeningAllowed => !_disposed && !SafeBoot.instance.safeMode.value;

  @override
  Future<bool> isAvailable() async {
    if (!listeningAllowed) return false;
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      return listeningAllowed && available == true;
    } on MissingPluginException {
      return false;
    } catch (error, stack) {
      await AppLog.instance.caught(
        'onnx_speech_availability_failed',
        error,
        stack,
      );
      return false;
    }
  }

  @override
  Future<bool> start() async {
    if (!listeningAllowed || _starting || _stopping != null) return false;
    if (_listening) return true;
    final generation = ++_startGeneration;
    final settled = Completer<void>();
    _startSettled = settled;
    _starting = true;
    try {
      if (!await isAvailable() ||
          !listeningAllowed ||
          generation != _startGeneration) {
        return false;
      }
      _nativeStartPending = true;
      final started = await _channel.invokeMethod<bool>('start') == true;
      _nativeStartPending = false;
      if (!listeningAllowed || generation != _startGeneration) {
        // A stop can reach native code before its pending start completes.
        // Stop again after that acknowledgement so capture cannot resume.
        if (started) await _stopNative(discard: true);
        return false;
      }
      _listening = started;
      return _listening;
    } catch (error, stack) {
      _listening = false;
      // An exceptional reply does not prove native capture never started.
      if (_nativeStartPending) await _stopNative(discard: true);
      await AppLog.instance.caught('onnx_speech_start_failed', error, stack);
      return false;
    } finally {
      _starting = false;
      _nativeStartPending = false;
      settled.complete();
      _startSettled = null;
    }
  }

  @override
  Future<String> stop() async {
    _startGeneration++;
    final shouldStop = _listening || _nativeStartPending;
    _listening = false;
    final stopping = _stopping;
    if (stopping != null) return stopping;
    if (!shouldStop) return '';
    final pendingStart = _nativeStartPending ? _startSettled?.future : null;
    final operation = _stopAndWait(pendingStart);
    _stopping = operation;
    try {
      return await operation;
    } finally {
      _stopping = null;
    }
  }

  Future<String> _stopAndWait(Future<void>? pendingStart) async {
    final generation = _startGeneration;
    final text = await _stopNative(discard: !listeningAllowed);
    // Native start can acknowledge after the first stop. Its cancelled start
    // path stops again; disposal/explicit stop must wait for that teardown.
    if (pendingStart != null) await pendingStart;
    return listeningAllowed && generation == _startGeneration ? text : '';
  }

  Future<String> _stopNative({bool discard = false}) async {
    final generation = _startGeneration;
    try {
      final text = await _channel.invokeMethod<String>('stop', {
        'discard': discard,
      });
      if (discard || !listeningAllowed || generation != _startGeneration) {
        return '';
      }
      return text ?? '';
    } catch (error, stack) {
      await AppLog.instance.caught('onnx_speech_stop_failed', error, stack);
      return '';
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'onSegment' || !listeningAllowed || !_listening) return;
    final raw = call.arguments;
    if (raw is! Map) return;
    final text = raw['text']?.toString() ?? '';
    final confidence = raw['confidence'];
    final pauseMs = raw['pause_ms'];
    _segments.add(
      NeuraSpeechSegment(
        engineId: id,
        text: text,
        isFinal: raw['is_final'] == true,
        confidence: confidence is num
            ? confidence.toDouble().clamp(0.0, 1.0).toDouble()
            : null,
        pauseBefore: Duration(
          milliseconds:
              pauseMs is num ? pauseMs.toInt().clamp(0, 60000).toInt() : 0,
        ),
        observedAtUtc: DateTime.now().toUtc(),
      ),
    );
  }

  void _onSafeModeChanged() {
    if (!listeningAllowed) unawaited(stop());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);
    _channel.setMethodCallHandler(null);
    await stop();
    await _segments.close();
  }
}
