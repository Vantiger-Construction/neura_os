import 'dart:async';

import 'package:flutter/services.dart';

import '../modules/core/app_log.dart';

/// Windows speech-to-text via a native WinRT bridge (see
/// windows/runner/neura_speech_recognizer.{h,cpp}).
///
/// The `speech_to_text` pub.dev package (used elsewhere in this app, e.g.
/// Voice Journal) has no Windows implementation — Android/iOS/web/macOS
/// only — so it fails at runtime on this desktop build. This talks to
/// Windows' own continuous dictation recognizer directly instead.
///
/// Exposes the same shape as VoiceJournalService (transcriptStream /
/// startRecording / stopRecording / dispose) so callers can be swapped
/// between the two without changing call sites.
class NeuraSpeechToTextService {
  // The underlying MethodChannel maps to a single native WinRT recognizer
  // session -- setMethodCallHandler can only safely have one owner. A second
  // instance would silently steal another owner's native callbacks (see the
  // wake-word listener, which needs to share this with the chat screen).
  static final NeuraSpeechToTextService instance = NeuraSpeechToTextService._();

  static const MethodChannel _channel =
      MethodChannel('neura/speech_recognition');

  final StreamController<String> _transcriptStream =
      StreamController.broadcast();

  // WinRT's ContinuousRecognitionSession fires 'onFinal' once per completed
  // phrase using its own built-in pause/endpoint detection — the session
  // itself keeps listening. This stream re-exposes just that "the user
  // finished a thought" signal (never partial hypotheses) so callers can
  // react to it directly, e.g. to auto-send in a hands-free chat loop
  // without requiring the user to tap "stop" themselves.
  final StreamController<String> _finalPhraseStream =
      StreamController.broadcast();

  String _finalText = '';
  bool _listening = false;
  Completer<String>? _stopCompleter;

  Stream<String> get transcriptStream => _transcriptStream.stream;
  Stream<String> get finalPhraseStream => _finalPhraseStream.stream;
  bool get isListening => _listening;

  NeuraSpeechToTextService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onListening':
        _finalText = '';
        break;
      case 'onPartial':
        final hypothesis = call.arguments as String? ?? '';
        _transcriptStream.add(
            _finalText.isEmpty ? hypothesis : '$_finalText $hypothesis');
        break;
      case 'onFinal':
        final phrase = call.arguments as String? ?? '';
        if (phrase.isNotEmpty) {
          _finalText = _finalText.isEmpty ? phrase : '$_finalText $phrase';
        }
        _transcriptStream.add(_finalText);
        if (phrase.trim().isNotEmpty) {
          _finalPhraseStream.add(_finalText);
        }
        break;
      case 'onStopped':
        _listening = false;
        if (!(_stopCompleter?.isCompleted ?? true)) {
          _stopCompleter!.complete(_finalText);
        }
        break;
      case 'onError':
        _listening = false;
        await AppLog.instance.error('speech_to_text_native_error', {'reason': call.arguments});
        _transcriptStream.add('[voice input error] ${call.arguments}');
        if (!(_stopCompleter?.isCompleted ?? true)) {
          _stopCompleter!.complete(_finalText);
        }
        break;
    }
  }

  Future<bool> startRecording() async {
    if (_listening) return true;
    _finalText = '';
    _listening = true;
    try {
      await _channel.invokeMethod('start');
      return true;
    } catch (e) {
      _listening = false;
      await AppLog.instance.error('speech_to_text_start_failed', {'error': e.toString()});
      _transcriptStream.add('Speech-to-text not available on this device.');
      return false;
    }
  }

  Future<String> stopRecording() async {
    if (!_listening) return _finalText;
    _stopCompleter = Completer<String>();
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {
      _listening = false;
      return _finalText;
    }
    return _stopCompleter!.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => _finalText,
    );
  }

  // Deliberately no dispose() -- this is a permanent app-lifetime singleton
  // (multiple features share the one underlying native recognizer session),
  // so closing its StreamControllers would break it for every other owner.
  // Callers that stop "owning" the mic (e.g. a screen closing) should call
  // stopRecording() instead.
}
