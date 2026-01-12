
import '../emotion/emotion_state.dart';
import 'neura_speech_state.dart';

class NeuraSpeechController {
  NeuraSpeechState fromEmotion(EmotionState e, {required bool shouldSpeak}) {
    if (!shouldSpeak) {
      return const NeuraSpeechState(
        speaking: false,
        pace: 1.0,
        allowSilence: true,
      );
    }

    final pace = (0.9 + e.arousal * 0.4 - e.stress * 0.3).clamp(0.6, 1.3);

    return NeuraSpeechState(
      speaking: true,
      pace: pace,
      allowSilence: false,
    );
  }
}
