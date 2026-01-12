import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

class NeuraSleepListener {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool isRecording = false;

  Future<void> initRecorder() async {
    await _recorder.openRecorder();
    await Permission.microphone.request();
  }

  Future<void> startListening() async {
    if (!isRecording && await Permission.microphone.isGranted) {
      await _recorder.startRecorder(toFile: 'neura_sleep_talk.aac');
      isRecording = true;
    }
  }

  Future<void> stopListening() async {
    if (isRecording) {
      await _recorder.stopRecorder();
      isRecording = false;
    }
  }

  Future<String?> getRecordedFilePath() async {
    // Return the last recorded file path if available
    return null; // TODO: Implement proper file path storage
  }

  Future<void> dispose() async {
    await _recorder.closeRecorder();
  }
}