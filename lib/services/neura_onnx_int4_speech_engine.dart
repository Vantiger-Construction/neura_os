import 'dart:async';

import 'package:flutter/services.dart';

import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';
import 'neura_speech_engine.dart';

/// Experimental native seam for an ONNX int4 streaming ASR candidate.
///
/// No model is bundled and no implementation is assumed. The adapter becomes
/// selectable only when a platform runner implements the channel and reports
/// availability. This keeps benchmark code provider-neutral without silently
/// changing the production recognizer.
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

  @override
  String get id => 'onnx_int4_experimental';

  @override
  NeuraSpeechEngineCapabilities get capabilities =>
      const NeuraSpeechEngineCapabilities(
        onDevice: true,
        supportsPartialResults: true,
        supportsConfidence: true,
        supportedPlatforms: {'windows', 'android'},
        experimental: true,
      );

  @override
  Stream<NeuraSpeechSegment> get segments => _segments.stream;

  @override
  bool get isListening => _listening;

  bool get listeningAllowed => !SafeBoot.instance.safeMode.value;

  @override
  Future<bool> isAvailable() async {
    if (!listeningAllowed) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') == true;
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
    if (!listeningAllowed || !await isAvailable()) return false;
    try {
      _listening = await _channel.invokeMethod<bool>('start') == true;
      if (!listeningAllowed && _listening) {
        await stop();
        return false;
      }
      return _listening;
    } catch (error, stack) {
      _listening = false;
      await AppLog.instance.caught('onnx_speech_start_failed', error, stack);
      return false;
    }
  }

  @override
  Future<String> stop() async {
    if (!_listening) return '';
    _listening = false;
    try {
      return await _channel.invokeMethod<String>('stop') ?? '';
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
          milliseconds: pauseMs is num
              ? pauseMs.toInt().clamp(0, 60000).toInt()
              : 0,
        ),
        observedAtUtc: DateTime.now().toUtc(),
      ),
    );
  }

  void _onSafeModeChanged() {
    if (!listeningAllowed && _listening) unawaited(stop());
  }

  Future<void> dispose() async {
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);
    await stop();
    await _segments.close();
  }
}
