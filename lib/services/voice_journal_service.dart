import 'dart:async';

class VoiceJournalService {
  /// Starts voice recording for a journal entry.
  Future<void> startRecording() async {
    // TODO: integrate STT recording
  }

  /// Stops recording and returns transcript.
  Future<String> stopRecording() async {
    // TODO: call STT API
    return '';
  }
}
