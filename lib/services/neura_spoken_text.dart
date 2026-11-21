/// Turns reply text into what Neura should actually say out loud.
///
/// Replies are shown as written, but text-to-speech reads markdown and emoji
/// literally or unpredictably ("asterisk asterisk soft boiled", "smiling face
/// with smiling eyes"). Models still produce them, especially the small
/// offline model, so speech is cleaned at the single speak() entry point.
abstract final class NeuraSpokenText {
  // Pictographs, symbols, flags, keycaps, skin tones, joiners and variation
  // selectors. Plain punctuation, letters and digits are never touched.
  static final _emoji = RegExp(
    '[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
    '\u{1F1E6}-\u{1F1FF}\u{FE0E}\u{FE0F}\u{200D}\u{20E3}\u{E0020}-\u{E007F}]',
    unicode: true,
  );
  static final _link = RegExp(r'\[([^\]]+)\]\((?:[^)\s]+)\)');
  static final _heading = RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true);
  static final _bullet =
      RegExp(r'^\s*(?:[-*+•]|\d{1,2}[.)])\s+', multiLine: true);
  static final _quote = RegExp(r'^\s*>\s?', multiLine: true);
  static final _rule = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$', multiLine: true);
  // Emphasis markers, but not a multiplication like "2*3" or "a * b".
  static final _emphasis =
      RegExp(r'(?<![\d\s])\*{1,3}|\*{1,3}(?![\d\s])|__|~~');
  static final _endsSentence = RegExp(r'[.!?:;,…]["”’)]*$');

  static String clean(String text) {
    var s = text.replaceAll('\r\n', '\n');
    s = s.replaceAllMapped(_link, (m) => m.group(1)!);
    s = s.replaceAll('`', '');
    s = s.replaceAll(_rule, '');
    s = s.replaceAll(_heading, '');
    s = s.replaceAll(_quote, '');

    // Each list item becomes its own sentence so the voice pauses between
    // items instead of running them together.
    final lines = s.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!_bullet.hasMatch(lines[i])) continue;
      var item = lines[i].replaceFirst(_bullet, '').trimRight();
      if (item.isNotEmpty && !_endsSentence.hasMatch(item)) item = '$item.';
      lines[i] = item;
    }
    s = lines.join('\n');

    s = s.replaceAll(_emphasis, '');
    s = s.replaceAll(_emoji, '');
    // Tidy spacing left behind ("happy  !" -> "happy!").
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAllMapped(RegExp(r' +([.,!?;:])'), (m) => m.group(1)!);
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.split('\n').map((l) => l.trim()).join('\n').trim();
  }
}
