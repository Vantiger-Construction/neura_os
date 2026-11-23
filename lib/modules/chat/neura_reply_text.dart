import 'package:flutter/widgets.dart';

/// Shows a Neura reply with its light markdown rendered instead of printed.
///
/// Models, especially the small offline one, answer with `**bold**`, `##`
/// headings and `-` lists. Chat bubbles are plain text, so those markers were
/// shown literally. This only changes how a reply looks: the stored reply,
/// model history, guardrail screening and speech all keep the original text.
///
/// Handles emphasis, headings, bullets, quotes, rules, code fences, inline
/// code and links. Anything else is shown as written. A link keeps its
/// address visible so a reply cannot hide where it points.
abstract final class NeuraReplyText {
  static final _fence = RegExp(r'^\s*```.*$');
  static final _rule = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$');
  static final _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$');
  static final _bullet = RegExp(r'^(\s*)[-*+•]\s+');
  static final _quote = RegExp(r'^\s*>\s?');
  static final _link = RegExp(r'\[([^\]\n]+)\]\(([^)\s]+)\)');
  static final _bold = RegExp(r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1');
  // Single-star emphasis, but not multiplication like "2*3" or "a * b".
  static final _italic =
      RegExp(r'(?<![\w*])\*(?=[^\s*\d])([^*\n]+?)(?<=\S)\*(?![\w*])');
  static final _strike = RegExp(r'~~(?=\S)(.+?)(?<=\S)~~');

  /// Whether [text] has anything to render; plain text is shown untouched.
  static bool hasMarkdown(String text) => span(text).toPlainText() != text;

  /// The reply as a [Text] widget: the original string when it has no
  /// markdown, otherwise rich text with the markers rendered.
  static Widget widget(String text) {
    if (!hasMarkdown(text)) return Text(text);
    return Text.rich(span(text));
  }

  static TextSpan span(String text) {
    final children = <InlineSpan>[];
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var first = true;
    for (var line in lines) {
      if (_fence.hasMatch(line)) continue;
      if (!first) children.add(const TextSpan(text: '\n'));
      first = false;
      if (_rule.hasMatch(line)) continue;
      final heading = _heading.firstMatch(line);
      if (heading != null) {
        children.add(TextSpan(
          style: const TextStyle(fontWeight: FontWeight.bold),
          children: _inline(heading.group(1)!),
        ));
        continue;
      }
      line = line.replaceFirst(_quote, '');
      line = line.replaceFirstMapped(_bullet, (m) => '${m.group(1)}• ');
      children.addAll(_inline(line));
    }
    return TextSpan(children: children);
  }

  static List<InlineSpan> _inline(String line) {
    line = line.replaceAllMapped(_link, (m) {
      final label = m.group(1)!, url = m.group(2)!;
      return label == url ? url : '$label ($url)';
    });
    line = line.replaceAll('`', '');
    line = line.replaceAllMapped(_strike, (m) => m.group(1)!);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _bold.allMatches(line)) {
      spans.addAll(_italics(line.substring(at, m.start)));
      spans.add(TextSpan(
        style: const TextStyle(fontWeight: FontWeight.bold),
        children: _italics(m.group(2)!),
      ));
      at = m.end;
    }
    spans.addAll(_italics(line.substring(at)));
    return spans;
  }

  static List<InlineSpan> _italics(String s) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _italic.allMatches(s)) {
      spans.add(TextSpan(text: _stray(s.substring(at, m.start))));
      spans.add(TextSpan(
        text: _stray(m.group(1)!),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
      at = m.end;
    }
    spans.add(TextSpan(text: _stray(s.substring(at))));
    return spans.where((t) => (t as TextSpan).text != '').toList();
  }

  // An unclosed "**" or "__", as in a reply still streaming in.
  static String _stray(String s) => s.replaceAll('**', '').replaceAll('__', '');
}
