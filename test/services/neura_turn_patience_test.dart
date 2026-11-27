import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_turn_patience.dart';

void main() {
  test('trailing-off phrases wait for the rest of the thought', () {
    for (final heard in [
      'I just feel like',
      'It was okay but',
      'So yesterday I went to the store and',
      'um',
      'I keep thinking about it,',
      'and then...',
      "I'm not sure if",
    ]) {
      expect(NeuraTurnPatience.soundsUnfinished(heard), isTrue, reason: heard);
      expect(NeuraTurnPatience.after(heard), NeuraTurnPatience.unfinished);
    }
  });

  test('finished phrases and short replies end the turn quickly', () {
    for (final heard in [
      'What time is it',
      'I had a really good day.',
      'Yes',
      'thanks',
      'No.',
      'Tell me a joke',
      '',
    ]) {
      expect(NeuraTurnPatience.soundsUnfinished(heard), isFalse, reason: heard);
    }
    expect(
        NeuraTurnPatience.after('What time is it'), NeuraTurnPatience.settled);
  });

  test('a heavy message gets a gentler pause, never a shorter one', () {
    expect(
      NeuraTurnPatience.after('I miss her so much', heavy: true),
      NeuraTurnPatience.gentle,
    );
    expect(
      NeuraTurnPatience.after('I miss her and', heavy: true),
      NeuraTurnPatience.unfinished,
    );
    expect(
      NeuraTurnPatience.gentle,
      greaterThan(NeuraTurnPatience.settled),
    );
  });
}
