class PostChatReflectionService {
  Future<String> generateReflection(String sessionText) async {
    if (sessionText.trim().isEmpty) return '';
    await Future.delayed(const Duration(milliseconds: 300));

    final sentences = sessionText
        .split(RegExp(r'[.!?]+'))
        .map((s) => s.trim())
        .where((s) => s.length > 20)
        .toList();

    if (sentences.isEmpty) return '';

    final sample = sentences.length <= 3
        ? sentences
        : [
            sentences.first,
            sentences[sentences.length ~/ 2],
            sentences.last,
          ];

    final buf = StringBuffer('In this session you explored: ');
    for (var i = 0; i < sample.length; i++) {
      buf.write('"');
      buf.write(sample[i]);
      buf.write('"');
      if (i < sample.length - 1) buf.write('. ');
    }
    buf.write(
        '. Notice any recurring themes — they often point to what needs attention most.');
    return buf.toString();
  }
}
