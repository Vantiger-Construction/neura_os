import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Lightweight local speech-to-text recorder using `speech_to_text`.
///
/// Notes:
/// - On Android/iOS you must request microphone permission.
/// - On desktop/web support depends on platform capabilities.
class VoiceJournalService {
  final stt.SpeechToText _stt = stt.SpeechToText();
  final StreamController<String> _transcriptStream = StreamController.broadcast();

  String _current = '';
  bool _listening = false;

  Stream<String> get transcriptStream => _transcriptStream.stream;
  bool get isListening => _listening;

  Future<bool> startRecording() async {
    if (_listening) return true;
    final available = await _stt.initialize(
      onError: (e) => _transcriptStream.add('[STT error] ${e.errorMsg}'),
      onStatus: (_) {},
    );
    if (!available) {
      _transcriptStream.add('Speech-to-text not available on this device.');
      return false;
    }

    _current = '';
    _listening = true;

    await _stt.listen(
      onResult: (r) {
        _current = r.recognizedWords;
        _transcriptStream.add(_current);
      },
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      cancelOnError: true,
    );

    return true;
  }

  Future<String> stopRecording() async {
    if (!_listening) return _current;
    _listening = false;
    await _stt.stop();
    return _current;
  }

  Future<void> dispose() async {
    await _stt.cancel();
    await _transcriptStream.close();
  }
}
