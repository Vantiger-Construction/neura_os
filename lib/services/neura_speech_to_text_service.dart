import 'dart:async';

import 'package:flutter/services.dart';

import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';
import 'neura_speech_engine.dart';

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
  final StreamController<NeuraSpeechSegment> _segmentStream =
      StreamController.broadcast();

  String _finalText = '';
  bool _listening = false;
  Completer<String>? _stopCompleter;
  Future<String>? _stopInFlight;
  DateTime? _lastFinalAtUtc;

  Stream<String> get transcriptStream => _transcriptStream.stream;
  Stream<String> get finalPhraseStream => _finalPhraseStream.stream;
  Stream<NeuraSpeechSegment> get segmentStream => _segmentStream.stream;
  bool get isListening => _listening;
  bool get listeningAllowed => !SafeBoot.instance.safeMode.value;

  NeuraSpeechToTextService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onListening':
        _finalText = '';
        _lastFinalAtUtc = null;
        break;
      case 'onPartial':
        if (!listeningAllowed) return;
        final hypothesis = call.arguments as String? ?? '';
        _transcriptStream
            .add(_finalText.isEmpty ? hypothesis : '$_finalText $hypothesis');
        _segmentStream.add(
          NeuraSpeechSegment(
            engineId: 'windows_winrt',
            text: hypothesis,
            isFinal: false,
            observedAtUtc: DateTime.now().toUtc(),
          ),
        );
        break;
      case 'onFinal':
        if (!listeningAllowed) return;
        final arguments = call.arguments;
        final phrase = arguments is Map
            ? arguments['text']?.toString() ?? ''
            : arguments as String? ?? '';
        final rawConfidence =
            arguments is Map ? arguments['confidence'] : null;
        final confidence = rawConfidence is num
            ? rawConfidence.toDouble().clamp(0.0, 1.0).toDouble()
            : null;
        final completedPhrase = phrase.trim();
        final observedAtUtc = DateTime.now().toUtc();
        final pauseBefore = _lastFinalAtUtc == null
            ? Duration.zero
            : observedAtUtc.difference(_lastFinalAtUtc!);
        if (completedPhrase.isNotEmpty) {
          _finalText = _finalText.isEmpty
              ? completedPhrase
              : '$_finalText $completedPhrase';
          _lastFinalAtUtc = observedAtUtc;
        }
        _transcriptStream.add(_finalText);
        if (completedPhrase.isNotEmpty) {
          _finalPhraseStream.add(completedPhrase);
          _segmentStream.add(
            NeuraSpeechSegment(
              engineId: 'windows_winrt',
              text: completedPhrase,
              isFinal: true,
              confidence: confidence,
              pauseBefore: pauseBefore,
              observedAtUtc: observedAtUtc,
            ),
          );
        }
        break;
      case 'onStopped':
        _listening = false;
        _completePendingStop();
        break;
      case 'onError':
        _listening = false;
        await AppLog.instance.error('speech_to_text_native_error');
        _transcriptStream.add('Speech-to-text reported an input error.');
        _completePendingStop();
        break;
    }
  }

  Future<bool> isAvailable() async {
    if (!listeningAllowed) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') == true;
    } on MissingPluginException {
      return false;
    } catch (error, stack) {
      await AppLog.instance.caught(
        'speech_to_text_availability_failed',
        error,
        stack,
      );
      return false;
    }
  }

  void _completePendingStop() {
    final completer = _stopCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(_finalText);
    }
  }

  Future<bool> startRecording() async {
    if (!listeningAllowed) return false;
    final stopping = _stopInFlight;
    if (stopping != null) await stopping;
    if (!listeningAllowed) return false;
    if (_listening) return true;

    _finalText = '';
    _listening = true;
    try {
      await _channel.invokeMethod('start');
      if (!listeningAllowed) {
        await stopRecording();
        return false;
      }
      return true;
    } catch (error, stack) {
      _listening = false;
      await AppLog.instance.caught(
        'speech_to_text_start_failed',
        error,
        stack,
      );
      _transcriptStream.add('Speech-to-text not available on this device.');
      return false;
    }
  }

  Future<String> stopRecording() {
    final existing = _stopInFlight;
    if (existing != null) return existing;
    if (!_listening) return Future<String>.value(_finalText);

    late final Future<String> operation;
    operation = _stopRecordingOnce().whenComplete(() {
      if (identical(_stopInFlight, operation)) _stopInFlight = null;
    });
    _stopInFlight = operation;
    return operation;
  }

  Future<String> _stopRecordingOnce() async {
    final completer = Completer<String>();
    _stopCompleter = completer;
    try {
      await _channel.invokeMethod('stop');
    } catch (error, stack) {
      _listening = false;
      _completePendingStop();
      await AppLog.instance.caught(
        'speech_to_text_stop_failed',
        error,
        stack,
      );
      if (identical(_stopCompleter, completer)) _stopCompleter = null;
      return _finalText;
    }

    try {
      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () async {
          _listening = false;
          _completePendingStop();
          await AppLog.instance.warn('speech_to_text_stop_timeout');
          return _finalText;
        },
      );
    } finally {
      if (identical(_stopCompleter, completer)) _stopCompleter = null;
    }
  }

  void _onSafeModeChanged() {
    if (!listeningAllowed && (_listening || _stopInFlight != null)) {
      unawaited(
        stopRecording().catchError((Object error, StackTrace stack) async {
          await AppLog.instance.caught(
            'speech_to_text_safe_mode_stop_failed',
            error,
            stack,
          );
          return _finalText;
        }),
      );
    }
  }

  // Deliberately no dispose() -- this is a permanent app-lifetime singleton
  // (multiple features share the one underlying native recognizer session),
  // so closing its StreamControllers would break it for every other owner.
  // Callers that stop "owning" the mic (e.g. a screen closing) should call
  // stopRecording() instead.
}
