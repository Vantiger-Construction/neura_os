import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_spoken_text.dart';

void main() {
  String clean(String s) => NeuraSpokenText.clean(s);

  test('plain sentences pass through unchanged', () {
    const text = "That's great news. How are you feeling about it?";
    expect(clean(text), text);
  });

  test('emoji are never read aloud', () {
    expect(clean('I am so happy for you! 😊🌟'), 'I am so happy for you!');
    expect(clean('Big hug 🫶 from me'), 'Big hug from me');
    expect(clean('Thumbs up 👍🏽 and ❤️'), 'Thumbs up and');
  });

  test('markdown emphasis, code and links are spoken as words', () {
    expect(clean('This is **really** important'), 'This is really important');
    expect(clean('Try *one* thing'), 'Try one thing');
    expect(clean('Run `flutter test` now'), 'Run flutter test now');
    expect(clean('See [the guide](https://example.com/x) first'),
        'See the guide first');
  });

  test('multiplication and math survive', () {
    expect(clean('2*3 is 6'), '2*3 is 6');
    expect(clean('a * b'), 'a * b');
  });

  test('list items become separate sentences', () {
    // The exact list the offline model produced for "how long to boil an egg".
    const reply = 'Sure! For a standard boiled egg:\n\n'
        '- **Soft-boiled**: 3 to 4 minutes\n'
        '- **Medium-boiled**: 5 to 6 minutes\n'
        '- **Hard-boiled**: 8 to 10 minutes.';
    expect(
      clean(reply),
      'Sure! For a standard boiled egg:\n\n'
      'Soft-boiled: 3 to 4 minutes.\n'
      'Medium-boiled: 5 to 6 minutes.\n'
      'Hard-boiled: 8 to 10 minutes.',
    );
    expect(clean('1. Breathe\n2) Pick one task'), 'Breathe.\nPick one task.');
  });

  test('headings, quotes and rules are dropped, not read', () {
    expect(clean('## Plan\nStart small.'), 'Plan\nStart small.');
    expect(clean('> quoted line'), 'quoted line');
    expect(clean('Before\n---\nAfter'), 'Before\n\nAfter');
  });

  test('nothing speakable leaves an empty string', () {
    expect(clean('🌟✨'), isEmpty);
    expect(clean('  '), isEmpty);
  });
}
