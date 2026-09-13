import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';
import 'neura_speech_to_text_service.dart';

/// Local speech-to-text used by Voice Journal.
///
/// Windows is routed through Neura's native WinRT recognizer because the
/// speech_to_text plugin is not the supported desktop path in this app.
/// Other supported platforms continue to use speech_to_text.
class VoiceJournalService {
  VoiceJournalService() {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  final stt.SpeechToText _stt = stt.SpeechToText();
  final StreamController<String> _pluginTranscriptStream =
      StreamController<String>.broadcast();

  bool get _usesNativeWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  NeuraSpeechToTextService get _native => NeuraSpeechToTextService.instance;

  String _current = '';
  bool _pluginListening = false;
  bool _disposed = false;

  Stream<String> get transcriptStream => _usesNativeWindows
      ? _native.transcriptStream
      : _pluginTranscriptStream.stream;

  bool get isListening =>
      _usesNativeWindows ? _native.isListening : _pluginListening;

  bool get listeningAllowed => !SafeBoot.instance.safeMode.value;

  Future<bool> startRecording() async {
    if (_disposed || !listeningAllowed) return false;
    if (_usesNativeWindows) {
      return _native.startRecording();
    }
    if (_pluginListening) return true;

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _pluginTranscriptStream.add(
          permission.isPermanentlyDenied
              ? 'Microphone access is disabled. Enable it in system settings.'
              : 'Microphone permission is required for voice journaling.',
        );
        return false;
      }
    }

    try {
      final available = await _stt.initialize(
        onError: (error) {
          _pluginListening = false;
          _pluginTranscriptStream.add(
            'Speech-to-text error: ${error.errorMsg}',
          );
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _pluginListening = false;
          }
        },
      );
      if (!available) {
        _pluginTranscriptStream.add(
          'Speech-to-text is not available on this device.',
        );
        return false;
      }

      _current = '';
      _pluginListening = true;
      await _stt.listen(
        onResult: (result) {
          if (_disposed || !listeningAllowed) return;
          _current = result.recognizedWords;
          _pluginTranscriptStream.add(_current);
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
      return _pluginListening;
    } catch (error, stack) {
      _pluginListening = false;
      await AppLog.instance.caught(
        'voice_journal_start_failed',
        error,
        stack,
      );
      if (!_disposed) {
        _pluginTranscriptStream.add(
          'Speech-to-text could not start on this device.',
        );
      }
      return false;
    }
  }

  Future<String> stopRecording() async {
    if (_usesNativeWindows) return _native.stopRecording();
    if (!_pluginListening) return _current;

    _pluginListening = false;
    try {
      await _stt.stop();
    } catch (error, stack) {
      await AppLog.instance.caught(
        'voice_journal_stop_failed',
        error,
        stack,
      );
    }
    return _current;
  }

  void _onSafeModeChanged() {
    if (!listeningAllowed && isListening) {
      unawaited(stopRecording());
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);

    if (_usesNativeWindows) {
      await _native.stopRecording();
    } else {
      _pluginListening = false;
      await _stt.cancel();
      await _pluginTranscriptStream.close();
    }
  }
}
