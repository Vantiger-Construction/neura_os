class SpeechItem {
  final String text;
  final double pace;
  final bool emotional;

  const SpeechItem({
    required this.text,
    required this.pace,
    this.emotional = false,
  });
}
