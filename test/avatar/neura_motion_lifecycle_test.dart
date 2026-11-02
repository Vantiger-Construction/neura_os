import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_animated_body.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/avatar/motion/neura_motion_engine.dart';
import 'package:neuro_companion/core/neura_event_bus.dart';
import 'package:neuro_companion/core/neura_events.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';

const _movingPose = NeuraPose(dx: 0.1, dy: -0.05, lean: 0.1, scale: 1.05);

Widget _host({
  NeuraPoseSampler? sampler,
  bool reduce = false,
  bool tickers = true,
  bool animate = true,
  bool respectLifecycle = true,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: TickerMode(
          enabled: tickers,
          child: SizedBox.square(
            dimension: 100,
            child: NeuraAnimatedBody(
              sampler: sampler,
              animate: animate,
              respectAppLifecycle: respectLifecycle,
              child: const SizedBox(),
            ),
          ),
        ),
      ),
    );

void _expectNeutral(WidgetTester tester) {
  final transforms = tester.widgetList<Transform>(
    find.descendant(
      of: find.byType(NeuraAnimatedBody),
      matching: find.byType(Transform),
    ),
  );
  expect(transforms, isNotEmpty);
  for (final transform in transforms) {
    expect(transform.transform.isIdentity(), isTrue);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ShellPrefs previousPrefs;
  late bool previousSafeMode;
  late bool previousRecovery;

  setUp(() {
    previousPrefs = ShellPrefsController.instance.prefs.value;
    previousSafeMode = SafeBoot.instance.safeMode.value;
    previousRecovery = SafeBoot.instance.restartRequired.value;
    NeuraMotion.instance.stop();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  tearDown(() {
    NeuraMotion.instance.stop();
    SafeBoot.instance.safeMode.value = previousSafeMode;
    SafeBoot.instance.restartRequired.value = previousRecovery;
    ShellPrefsController.instance.prefs.value = previousPrefs;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final state in AppLifecycleState.values.where(
    (s) => s != AppLifecycleState.resumed,
  )) {
    testWidgets('custom sampler stops at $state and recovers in foreground', (
      tester,
    ) async {
      var samples = 0;
      NeuraPose sample() {
        samples++;
        return _movingPose;
      }

      await tester.pumpWidget(_host(sampler: sample));
      await tester.pump(const Duration(milliseconds: 100));
      expect(samples, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(state);
      final before = samples;
      await tester.pump(const Duration(seconds: 1));
      expect(samples, before);
      _expectNeutral(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(samples, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('mounting while inactive never samples until resumed', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    var samples = 0;
    NeuraPose sample() {
      samples++;
      return _movingPose;
    }

    await tester.pumpWidget(_host(sampler: sample));
    await tester.pump(const Duration(seconds: 1));
    expect(samples, 0);
    _expectNeutral(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(samples, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion, ticker cover and animate reset then recover', (
    tester,
  ) async {
    var samples = 0;
    NeuraPose sample() {
      samples++;
      return _movingPose;
    }

    await tester.pumpWidget(_host(sampler: sample));
    for (final blocked in [
      _host(sampler: sample, reduce: true),
      _host(sampler: sample, tickers: false),
      _host(sampler: sample, animate: false),
    ]) {
      await tester.pumpWidget(blocked);
      final before = samples;
      await tester.pump(const Duration(seconds: 1));
      expect(samples, before);
      _expectNeutral(tester);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(_host(sampler: sample));
      await tester.pump(const Duration(milliseconds: 100));
      expect(samples, greaterThan(before));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'mascot lifecycle exception still honors explicit and accessibility gates',
    (tester) async {
      var samples = 0;
      NeuraPose sample() {
        samples++;
        return _movingPose;
      }

      await tester.pumpWidget(_host(sampler: sample, respectLifecycle: false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final before = samples;
      await tester.pump(const Duration(milliseconds: 100));
      expect(samples, greaterThan(before));
      for (final blocked in [
        _host(sampler: sample, respectLifecycle: false, animate: false),
        _host(sampler: sample, respectLifecycle: false, reduce: true),
        _host(sampler: sample, respectLifecycle: false, tickers: false),
        _host(sampler: sample),
      ]) {
        await tester.pumpWidget(blocked);
        final stopped = samples;
        await tester.pump(const Duration(seconds: 1));
        expect(samples, stopped);
        _expectNeutral(tester);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
      'sampler replacement follows its source and disposal stops frames', (
    tester,
  ) async {
    var samples = 0;
    NeuraPose sample() {
      samples++;
      return _movingPose;
    }

    await tester.pumpWidget(_host(sampler: sample));
    await tester.pumpWidget(_host());
    expect(tester.binding.transientCallbackCount, 0);
    NeuraMotion.instance.start();
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(_host(sampler: sample));
    NeuraMotion.instance.stop();
    final before = samples;
    await tester.pump(const Duration(milliseconds: 100));
    expect(samples, greaterThan(before));
    await tester.pumpWidget(_host());
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    NeuraMotion.instance.start();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Safe Mode, recovery and Still suspend shared motion and allow recovery',
    (tester) async {
      NeuraMotion.instance.start();
      await tester.pumpWidget(_host());
      for (final blocker in [
        SafeBoot.instance.safeMode,
        SafeBoot.instance.restartRequired,
      ]) {
        blocker.value = true;
        await tester.pump();
        expect(NeuraMotion.instance.live.value, isFalse);
        expect(NeuraMotion.instance.sample(), same(NeuraPose.neutral));
        _expectNeutral(tester);
        expect(tester.binding.transientCallbackCount, 0);
        blocker.value = false;
        await tester.pump();
        expect(NeuraMotion.instance.live.value, isTrue);
        expect(tester.binding.transientCallbackCount, greaterThan(0));
      }
      ShellPrefsController.instance.prefs.value = ShellPrefs.defaults.copyWith(
        companionMotion: NeuraCompanionMotion.still,
      );
      await tester.pump();
      expect(NeuraMotion.instance.live.value, isFalse);
      _expectNeutral(tester);
      ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
      await tester.pump();
      expect(NeuraMotion.instance.live.value, isTrue);
      NeuraEventBus.I.emit(NeuraErrorEvent('Synthetic motion error'));
      await tester.pump();
      NeuraMotion.instance.stop();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(NeuraMotion.instance.sample(), same(NeuraPose.neutral));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  test('Still stops a moving pose immediately', () {
    final engine = NeuraMotionEngine();
    engine.setPhase(NeuraBodyPhase.speaking);
    engine.setMouthOpen(1);
    for (var i = 0; i < 30; i++) {
      engine.tick(0.016);
    }
    engine.setMotionLevel(NeuraBodyMotionLevel.still);
    expect(engine.tick(0.016), same(NeuraPose.neutral));
  });
}
