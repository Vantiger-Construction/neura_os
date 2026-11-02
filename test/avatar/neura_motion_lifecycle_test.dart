import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_animated_body.dart';
import 'package:neuro_companion/avatar/motion/neura_motion_engine.dart';

void main() {
  testWidgets(
      'body stops sampling in background, reduced motion and disabled tickers',
      (tester) async {
    var samples = 0;
    NeuraPose sample() {
      samples++;
      return NeuraPose.neutral;
    }

    Widget host({bool reduce = false, bool tickers = true}) => MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: TickerMode(
                enabled: tickers,
                child: SizedBox(
                    width: 100,
                    height: 100,
                    child: NeuraAnimatedBody(
                        sampler: sample, child: const SizedBox())))));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 100));
    expect(samples, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final before = samples;
    await tester.pump(const Duration(seconds: 1));
    expect(samples, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(host(reduce: true));
    final reduced = samples;
    await tester.pump(const Duration(seconds: 1));
    expect(samples, reduced);
    await tester.pumpWidget(host(tickers: false));
    final hidden = samples;
    await tester.pump(const Duration(seconds: 1));
    expect(samples, hidden);
    await tester.pumpWidget(const SizedBox());
  });
  test('Still stops a moving pose immediately', () {
    final engine = NeuraMotionEngine();
    engine.setPhase(NeuraBodyPhase.speaking);
    engine.setMouthOpen(1);
    for (var i = 0; i < 30; i++) {
      engine.tick(0.016);
    }
    engine.setMotionLevel(NeuraBodyMotionLevel.still);
    expect(engine.tick(0.016), NeuraPose.neutral);
  });
}
