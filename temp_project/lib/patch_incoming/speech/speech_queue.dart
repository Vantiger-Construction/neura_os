import 'speech_item.dart';

class SpeechQueue {
  final List<SpeechItem> _queue = [];
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  void enqueue(SpeechItem item) => _queue.add(item);

  SpeechItem? next() {
    if (_queue.isEmpty) return null;
    _speaking = true;
    return _queue.removeAt(0);
  }

  void done() => _speaking = false;
}
