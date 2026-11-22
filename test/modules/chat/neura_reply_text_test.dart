import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/chat/neura_reply_text.dart';

void main() {
  String shown(String s) => NeuraReplyText.span(s).toPlainText();

  List<TextSpan> styled(String s, bool Function(TextStyle) test) {
    final found = <TextSpan>[];
    void walk(InlineSpan span, TextStyle inherited) {
      if (span is! TextSpan) return;
      final style = inherited.merge(span.style);
      if (span.text != null && span.text!.isNotEmpty && test(style)) {
        found.add(TextSpan(text: span.text));
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, style);
      }
    }

    walk(NeuraReplyText.span(s), const TextStyle());
    return found;
  }

  List<String> bold(String s) =>
      styled(s, (t) => t.fontWeight == FontWeight.bold)
          .map((t) => t.text!)
          .toList();
  List<String> italic(String s) =>
      styled(s, (t) => t.fontStyle == FontStyle.italic)
          .map((t) => t.text!)
          .toList();

  test('plain replies are shown exactly as written', () {
    for (final text in [
      "That's great news. How are you feeling about it?",
      '2*3 is 6, and a * b is fine.',
      'Line one\n\nLine two',
      'See [1] and [2].',
    ]) {
      expect(NeuraReplyText.hasMarkdown(text), isFalse, reason: text);
      expect(NeuraReplyText.widget(text), isA<Text>());
      expect((NeuraReplyText.widget(text) as Text).data, text);
    }
  });

  test('emphasis is rendered, not printed', () {
    expect(shown('This is **really** important'), 'This is really important');
    expect(bold('This is **really** important'), ['really']);
    expect(shown('Try *one* thing'), 'Try one thing');
    expect(italic('Try *one* thing'), ['one']);
    expect(bold('__Note__: rest'), ['Note']);
    expect(shown('~~old~~ new'), 'old new');
    expect(shown('Run `flutter test` now'), 'Run flutter test now');
  });

  test('the boiled egg list from the offline model reads cleanly', () {
    const reply = 'Sure! For a standard boiled egg:\n\n'
        '- **Soft-boiled**: 3 to 4 minutes\n'
        '- **Medium-boiled**: 5 to 6 minutes\n'
        '* **Hard-boiled**: 8 to 10 minutes.';
    expect(
      shown(reply),
      'Sure! For a standard boiled egg:\n\n'
      '• Soft-boiled: 3 to 4 minutes\n'
      '• Medium-boiled: 5 to 6 minutes\n'
      '• Hard-boiled: 8 to 10 minutes.',
    );
    expect(bold(reply), ['Soft-boiled', 'Medium-boiled', 'Hard-boiled']);
    expect(
        shown('1. Breathe\n2. Pick one task'), '1. Breathe\n2. Pick one task');
  });

  test('headings, quotes, rules and code fences', () {
    expect(
        shown('## A small plan\nStart small.'), 'A small plan\nStart small.');
    expect(bold('## A small plan\nStart small.'), ['A small plan']);
    expect(shown('> quoted line'), 'quoted line');
    expect(shown('Before\n---\nAfter'), 'Before\n\nAfter');
    expect(shown('Try:\n```\nbreathe in\n```'), 'Try:\nbreathe in');
  });

  test('links keep their address visible', () {
    expect(shown('See [the guide](https://example.com/x) first'),
        'See the guide (https://example.com/x) first');
    expect(shown('[https://a.org](https://a.org)'), 'https://a.org');
  });

  test('a reply still streaming in shows no stray markers', () {
    expect(shown('This is **reall'), 'This is reall');
    expect(shown('**'), '');
  });

  testWidgets('renders inside a bubble', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NeuraReplyText.widget('Hi **there**')),
    ));
    expect(find.text('Hi there'), findsOneWidget);
  });
}
