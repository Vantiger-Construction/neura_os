import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class SleepListenerService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  String? _currentPath;

  bool get isRecording => _recording;

  Future<void> startRecording() async {
    if (_recording) return;
    if (!await _recorder.hasPermission()) return;

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/sleep_$ts.m4a';
    _currentPath = path;

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );
      _recording = true;
    } catch (_) {
      _currentPath = null;
    }
  }

  Future<String> stopRecording() async {
    if (!_recording) return '';
    _recording = false;
    try {
      final path = await _recorder.stop();
      _currentPath = path;
    } catch (_) {}
    return _currentPath ?? '';
  }

  Future<void> deleteLastRecording() async {
    final path = _currentPath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      _currentPath = null;
    }
  }

  void dispose() => _recorder.dispose();
}