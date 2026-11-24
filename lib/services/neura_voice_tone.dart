import 'emotion_analysis_service.dart';

/// How Neura's voice leans for one reply: small multipliers on the user's
/// own rate and pitch, never a different voice. Slower and a touch lower when
/// someone is struggling; a little brighter for good news.
///
/// Built only from the on-device [EmotionRead] of their latest message;
/// nothing is stored. The changes stay subtle (at most about 12%) so the
/// voice still sounds like her and remains easy to follow.
class NeuraVoiceTone {
  final double rate;
  final double pitch;

  const NeuraVoiceTone._(this.rate, this.pitch);

  static const neutral = NeuraVoiceTone._(1, 1);

  /// Calm and steady: used after crisis language, whatever else was read.
  static const steady = NeuraVoiceTone._(0.88, 0.96);

  static const _heavy = {'sadness', 'grief', 'loneliness', 'shame'};
  static const _tense = {'anxiety', 'overwhelm', 'anger'};

  factory NeuraVoiceTone.forFeeling(EmotionRead read, {bool crisis = false}) {
    if (crisis) return steady;
    final feeling = read.primary;
    if (feeling == null) {
      return read.masked ? const NeuraVoiceTone._(0.95, 0.98) : neutral;
    }
    // Weak signals barely move the voice; strong ones reach the full lean.
    final strength = (0.5 + read.intensity / 2).clamp(0.5, 1.0);
    double lean(double full) => 1 + (full - 1) * strength;
    if (feeling == 'joy') {
      // "Relieved but exhausted" is not a moment for a brighter voice.
      if (read.secondary != null && read.secondary != 'joy') {
        return NeuraVoiceTone._(lean(0.96), 1);
      }
      return NeuraVoiceTone._(lean(1.06), lean(1.05));
    }
    if (_heavy.contains(feeling) || feeling == 'exhaustion') {
      return NeuraVoiceTone._(lean(0.88), lean(0.96));
    }
    if (_tense.contains(feeling)) {
      // Steady rather than soft: slower, an even pitch.
      return NeuraVoiceTone._(lean(0.9), lean(0.98));
    }
    return neutral;
  }

  @override
  bool operator ==(Object other) =>
      other is NeuraVoiceTone && other.rate == rate && other.pitch == pitch;

  @override
  int get hashCode => Object.hash(rate, pitch);

  @override
  String toString() => 'NeuraVoiceTone(rate: $rate, pitch: $pitch)';
}
