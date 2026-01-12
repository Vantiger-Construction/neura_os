
class NeuraSpeechState {
  final bool speaking;
  final double pace; // 0.5 slow – 1.5 fast
  final bool allowSilence;

  const NeuraSpeechState({
    required this.speaking,
    required this.pace,
    required this.allowSilence,
  });
}
