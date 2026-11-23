import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';

void main() {
  int end(String text, [int from = 0]) =>
      NeuraAiService.sentenceReleaseEnd(text, from);

  test('releases only sentences followed by whitespace', () {
    expect(end('Hello there'), 0);
    expect(end('Hello there.'), 0); // Could still become "there.5" or "...".
    expect(end('Hello there. How'), 12);
    expect(end('One! Two? Thr'), 9);
    expect(end('Pi is 3.14 today'), 0);
    expect(end('Line one\nLine'), 9);
  });

  test('never moves backwards past already released text', () {
    const text = 'First. Second. Thi';
    expect(end(text), 14);
    expect(end(text, 14), 14);
    expect(end('First. Sec', 7), 7);
  });
}
