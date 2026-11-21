import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/avatar_controller.dart';
import 'package:neuro_companion/avatar/avatar_registry.dart';
import 'package:neuro_companion/avatar/avatar_types.dart';
import 'package:neuro_companion/avatar/avatar_view.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/avatar/motion/neura_motion_engine.dart';
import 'package:neuro_companion/avatar/renderers/nebula_avatar_view.dart';
import 'package:neuro_companion/avatar/renderers/neura_mouth_layer.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/avatar_selector_screen.dart';
import 'package:neuro_companion/services/avatar_service.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _captureKey = ValueKey('nebula-pose-capture');

void _setSignals(AvatarController controller, String phase) {
  controller.setTalking(false);
  controller.setListening(phase == 'listening');
  if (phase == 'talking') {
    controller.setTalking(true);
    controller.setNumberInput('viseme', NeuraViseme.AI.index.toDouble());
    controller.setNumberInput('mouthOpen', 0.6);
  }
}

Future<void> _expectArmsAtSides(
  ui.Image image,
  Offset Function(Offset) toPixel, {
  required String reason,
}) async {
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  int alphaAt(Offset designPoint) {
    final point = toPixel(designPoint);
    // A hand outside the captured widget is a clipping failure, not an empty
    // pixel that may be ignored by the pose assertions below.
    final x = point.dx.floor();
    final y = point.dy.floor();
    expect(x, inInclusiveRange(0, image.width - 1), reason: reason);
    expect(y, inInclusiveRange(0, image.height - 1), reason: reason);
    return pixels.getUint8(
      (y * image.width + x) * 4 + 3,
    );
  }

  for (final handX in [700.0, 1220.0]) {
    final center = Offset(handX, 848);
    expect(alphaAt(center), greaterThanOrEqualTo(240),
        reason: '$reason: hand at hip level ($handX)');
    // Also check the hand's width and lower portion so a clipped tip or a
    // single painted dot cannot satisfy the center-only regression.
    for (final offset in const [Offset(-16, 0), Offset(16, 0), Offset(0, 32)]) {
      expect(alphaAt(center + offset), greaterThan(64),
          reason: '$reason: complete hand ($handX, $offset)');
    }
  }
  for (final point in const [
    Offset(700, 550),
    Offset(1220, 550),
    Offset(1222, 390),
  ]) {
    expect(alphaAt(point), 0,
        reason: '$reason: no extended arm or old raised hand at $point');
  }
}

Future<void> _expectWidgetArms(
  WidgetTester tester, {
  double pixelRatio = 1,
  required String reason,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final body = tester.renderObject<RenderBox>(find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is NeuraNebulaPainter,
  ));
  Offset toPixel(Offset point) {
    final local = Offset(
      (point.dx - 520) * body.size.width / 880,
      (point.dy - 80) * body.size.height / 880,
    );
    // Follow the real widget transforms: talking/listening sway may move the
    // whole body, but must never raise an arm relative to her torso.
    return body.localToGlobal(local, ancestor: boundary) * pixelRatio;
  }

  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      expect(image.width, (boundary.size.width * pixelRatio).ceil());
      expect(image.height, (boundary.size.height * pixelRatio).ceil());
      await _expectArmsAtSides(image, toPixel, reason: reason);
    } finally {
      image.dispose();
    }
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const nebula = AvatarRegistry.nebulaId;
  late ShellPrefs originalPrefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    originalPrefs = ShellPrefsController.instance.prefs.value;
    NeuraMotion.instance.stop();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NeuraPrefsCache.prefs.clear();
    AvatarService.instance.resetForTesting();
  });
  tearDown(() {
    NeuraMotion.instance.stop();
    AvatarService.instance.resetAfterDataWipe();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = originalPrefs;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  Widget avatar(
    AvatarController controller, {
    bool reduceMotion = false,
    double size = 128,
    double pixelRatio = 1,
    bool animateBody = false,
    bool showAura = true,
  }) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduceMotion,
            devicePixelRatio: pixelRatio,
          ),
          child: Center(
            child: RepaintBoundary(
              key: _captureKey,
              child: AvatarView(
                spec: AvatarRegistry.byId(nebula),
                controller: controller,
                size: size,
                animateBody: animateBody,
                showAura: showAura,
              ),
            ),
          ),
        ),
      );

  NeuraNebulaPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<NeuraNebulaPainter>()
      .single;

  test('nebula is a built-in avatar with no asset', () {
    final spec = AvatarRegistry.byId(nebula);
    expect(spec.id, nebula);
    expect(spec.format, AvatarFormat.nebula);
    expect(spec.assetPath, isEmpty);
  });

  for (final phase in ['idle', 'talking', 'listening']) {
    test('the painted $phase pose keeps both hands down across time', () async {
      final controller = AvatarController();
      final seconds = ValueNotifier<double>(0);
      addTearDown(controller.dispose);
      addTearDown(seconds.dispose);
      _setSignals(controller, phase);

      for (final time in [0.0, 0.75, 3.25]) {
        seconds.value = time;
        final recorder = ui.PictureRecorder();
        NeuraNebulaPainter(seconds: seconds, controller: controller)
            .paint(Canvas(recorder), const Size.square(880));
        final picture = recorder.endRecording();
        try {
          final image = picture.toImageSync(880, 880);
          try {
            await _expectArmsAtSides(
              image,
              (point) => point - const Offset(520, 80),
              reason: '$phase at ${time}s',
            );
          } finally {
            image.dispose();
          }
        } finally {
          picture.dispose();
        }
      }
    });
  }

  // Selector preview, normal avatar, and main-menu fallback sizes, at normal
  // and fractional Windows display scaling. Capture the mouth and shared body
  // transforms too; omit the decorative floor aura to measure body pixels.
  for (final size in [48.0, 128.0, 168.0]) {
    for (final pixelRatio in [1.0, 1.5]) {
      testWidgets('complete avatar keeps arms down at $size and ${pixelRatio}x',
          (tester) async {
        final controller = AvatarController();
        addTearDown(controller.dispose);
        tester.view.devicePixelRatio = pixelRatio;
        addTearDown(tester.view.resetDevicePixelRatio);
        NeuraMotion.instance.start();
        await tester.pumpWidget(avatar(
          controller,
          size: size,
          pixelRatio: pixelRatio,
          animateBody: true,
          showAura: false,
        ));
        await tester.pump();

        for (final phase in ['idle', 'talking', 'listening']) {
          _setSignals(controller, phase);
          NeuraMotion.instance.engine.setPhase(switch (phase) {
            'talking' => NeuraBodyPhase.speaking,
            'listening' => NeuraBodyPhase.listening,
            _ => NeuraBodyPhase.idle,
          });
          for (final elapsed in const [
            Duration(milliseconds: 16),
            Duration(milliseconds: 750),
            Duration(milliseconds: 2250),
          ]) {
            await tester.pump(elapsed);
            await _expectWidgetArms(
              tester,
              pixelRatio: pixelRatio,
              reason: '$phase at ${painter(tester).seconds.value}s, $size',
            );
          }
          expect(painter(tester).seconds.value, greaterThan(0));
          if (phase == 'talking') {
            final mouth = tester
                .widgetList<CustomPaint>(find.byType(CustomPaint))
                .map((widget) => widget.painter)
                .whereType<NebulaMouthPainter>()
                .single;
            expect(mouth.pose.open, 0.6);
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('time holds still until motion is live, and again on Still',
      (tester) async {
    final controller = AvatarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(avatar(
      controller,
      animateBody: true,
      showAura: false,
    ));
    await tester.pump();
    expect(find.byType(NebulaAvatarView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).seconds.value, 0);

    NeuraMotion.instance.start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    final moving = painter(tester).seconds.value;
    expect(moving, greaterThan(0));
    _setSignals(controller, 'talking');
    await tester.pump();
    await _expectWidgetArms(tester, reason: 'talking before Still');

    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults
        .copyWith(companionMotion: NeuraCompanionMotion.still);
    await tester.pump();
    final held = painter(tester).seconds.value;
    expect(held, greaterThanOrEqualTo(moving));
    await _expectWidgetArms(tester, reason: 'entering Still');
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).seconds.value, held);
    await _expectWidgetArms(tester, reason: 'held on Still');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion keeps her still before and after live motion',
      (tester) async {
    final controller = AvatarController();
    addTearDown(controller.dispose);
    NeuraMotion.instance.start();
    Widget host(bool reduce) => avatar(
          controller,
          reduceMotion: reduce,
          animateBody: true,
          showAura: false,
        );
    await tester.pumpWidget(host(true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).seconds.value, 0);
    await _expectWidgetArms(tester, reason: 'initial reduced motion');

    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    expect(painter(tester).seconds.value, greaterThan(0));
    _setSignals(controller, 'listening');
    await tester.pump();
    await _expectWidgetArms(tester, reason: 'listening before reduced motion');

    await tester.pumpWidget(host(true));
    final held = painter(tester).seconds.value;
    expect(held, greaterThan(0));
    await _expectWidgetArms(tester, reason: 'entering reduced motion');
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).seconds.value, held);
    await _expectWidgetArms(tester, reason: 'held on reduced motion');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mouth of light follows a fresh utterance and rests on Still',
      (tester) async {
    final controller = AvatarController();
    addTearDown(controller.dispose);
    NeuraMotion.instance.start();
    await tester.pumpWidget(avatar(controller));
    await tester.pump();
    NeuraMouthPose pose() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<NebulaMouthPainter>()
        .single
        .pose;
    void start() {
      controller.setTalking(false);
      controller.setTalking(true);
      controller.setNumberInput('viseme', NeuraViseme.AI.index.toDouble());
      controller.setNumberInput('mouthOpen', 0.6);
    }

    expect(pose(), NeuraMouthPose.rest);
    start();
    await tester.pump();
    expect(pose().open, 0.6);
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults
        .copyWith(companionMotion: NeuraCompanionMotion.still);
    await tester.pump();
    expect(pose(), NeuraMouthPose.rest);
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
    await tester.pump();
    controller.setNumberInput('mouthOpen', 0.8);
    await tester.pump();
    expect(pose(), NeuraMouthPose.rest);
    start();
    await tester.pump();
    expect(pose().open, 0.6);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selector previews the nebula still and saves the choice',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AvatarSelectorScreen()));
    await tester.pumpAndSettle();
    final preview = find.byType(NebulaAvatarView);
    expect(preview, findsOneWidget);
    expect(tester.widget<NebulaAvatarView>(preview).enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey(nebula)));
    await tester.pumpAndSettle();
    expect(AvatarService.instance.selectedAvatarId.value, nebula);
    await tester.pumpWidget(const SizedBox());
  });
}
