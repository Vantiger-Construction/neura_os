import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_audio_focus.dart';

void main() {
  test('speech focus stays active until every lease is released', () {
    final focus = NeuraAudioFocus.instance;
    final events = <bool>[];
    final subscription = focus.speechActivity.listen(events.add);

    final first = focus.acquireSpeech();
    final second = focus.acquireSpeech();

    expect(focus.speechActive, isTrue);
    expect(events, <bool>[true]);

    first.release();
    expect(focus.speechActive, isTrue);
    expect(events, <bool>[true]);

    second.release();
    expect(focus.speechActive, isFalse);
    expect(events, <bool>[true, false]);

    second.release();
    expect(events, <bool>[true, false]);
    subscription.cancel();
  });
}
