import 'speech_stream_chunker.dart';

/// Serial local playback. Cancelling invalidates queued chunks before they speak.
class ReplySpeechQueue {
  ReplySpeechQueue({required this.speak, required this.allowed});
  final Future<void> Function(String) speak;
  final bool Function() allowed;
  final _chunker = SpeechStreamChunker();
  Future<void> _tail = Future<void>.value();
  bool _cancelled = false;

  void add(String fullText) =>
      _enqueue(_chunker.extractReadyChunk('reply', fullText));

  Future<void> finish(String fullText) {
    _enqueue(_chunker.finish('reply', fullText));
    return _tail;
  }

  void cancel() {
    _cancelled = true;
    _chunker.discard('reply');
  }

  void _enqueue(String text) {
    if (text.isEmpty || _cancelled) return;
    _tail = _tail.then((_) async {
      if (!_cancelled && allowed()) await speak(text);
    }).catchError((Object _) {
      // Speech failure must not lose an otherwise valid text reply.
      cancel();
    });
  }
}
