import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

class TranscriptionService {
  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;

  Future<bool> _ensureInit() async {
    if (_initialized) return true;
    try {
      _initialized = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  /// Transcribes via the device STT engine. [audioPath] is reserved for
  /// future server-side STT; live mic is used when the path is unavailable.
  Future<String> transcribe(String audioPath) async {
    if (!await _ensureInit()) return '';
    final completer = Completer<String>();
    try {
      await _stt.listen(
        onResult: (r) {
          if (r.finalResult && !completer.isCompleted) {
            completer.complete(r.recognizedWords);
          }
        },
        listenOptions: const SpeechListenOptions(
          listenFor: Duration(seconds: 30),
          pauseFor: Duration(seconds: 4),
          localeId: 'en_US',
        ),
      );
    } catch (_) {
      return '';
    }
    return completer.future.timeout(const Duration(seconds: 35), onTimeout: () {
      unawaited(_stt.stop().catchError((_) {}));
      return '';
    });
  }

  /// Live transcription with optional partial-result callback.
  Future<String> transcribeLive({
    void Function(String partial)? onPartial,
    Duration listenFor = const Duration(seconds: 60),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!await _ensureInit()) return '';
    final completer = Completer<String>();
    try {
      await _stt.listen(
        onResult: (r) {
          onPartial?.call(r.recognizedWords);
          if (r.finalResult && !completer.isCompleted) {
            completer.complete(r.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: listenFor,
          pauseFor: pauseFor,
          localeId: 'en_US',
        ),
      );
    } catch (_) {
      return '';
    }
    return completer.future.timeout(
      listenFor + const Duration(seconds: 5),
      onTimeout: () {
        unawaited(_stt.stop().catchError((_) {}));
        return '';
      },
    );
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
