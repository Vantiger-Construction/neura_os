import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_voice_pack.dart';

void main() {
  test('fallback visemes evolve across consecutive playback frames', () {
    final fallback = NeuraVisemeFallback();

    final first = fallback.tick(talkLevel: 0.65, dt: 1 / 30);
    final firstFrame = [
      first.rest,
      first.aa,
      first.ee,
      first.oo,
      first.ff,
      first.mm,
    ];

    final second = fallback.tick(talkLevel: 0.65, dt: 1 / 30);
    final secondFrame = [
      second.rest,
      second.aa,
      second.ee,
      second.oo,
      second.ff,
      second.mm,
    ];

    expect(secondFrame, isNot(equals(firstFrame)));
    expect(
      secondFrame.reduce((left, right) => left + right),
      closeTo(1.0, 1e-9),
    );
  });
}
