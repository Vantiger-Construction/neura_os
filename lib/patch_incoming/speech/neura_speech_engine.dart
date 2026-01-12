import 'dart:async';
import '../emotion/emotion_core.dart';
import '../presence/neura_presence_controller.dart';
import 'speech_queue.dart';
import 'speech_item.dart';

class NeuraSpeechEngine {
  final EmotionCore emotion;
  final NeuraPresenceController presence;
  final SpeechQueue _queue = SpeechQueue();

  NeuraSpeechEngine({
    required this.emotion,
    required this.presence,
  });

  void speak(String text) {
    final e = emotion.latest;
    if (e == null) return;

    final pace =
        (0.9 + e.arousal * 0.4 - e.stress * 0.3).clamp(0.6, 1.3);

    _queue.enqueue(SpeechItem(text: text, pace: pace));
    if (!_queue.isSpeaking) _process();
  }

  void _process() {
    final item = _queue.next();
    if (item == null) return;

    presence.setSpeaking(true);

    Future.delayed(
      Duration(milliseconds: (item.text.length * 40 / item.pace).toInt()),
      () {
        presence.setSpeaking(false);
        _queue.done();
        _process();
      },
    );
  }
}
