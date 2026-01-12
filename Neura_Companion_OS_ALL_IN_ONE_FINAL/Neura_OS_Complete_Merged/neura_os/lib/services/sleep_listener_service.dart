import 'dart:async';

class SleepListenerService {
  /// Starts recording audio during sleep.
  Future<void> startRecording() async {
    // TODO: integrate device mic or wearable API
  }

  /// Stops recording and returns path to audio file.
  Future<String> stopRecording() async {
    // TODO: stop and save recording
    return '';
  }
}
