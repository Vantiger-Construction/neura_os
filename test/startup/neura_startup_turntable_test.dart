import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_boot_screen.dart';
import 'package:neuro_companion/startup/neura_startup_avatar.dart';
import 'package:neuro_companion/startup/neura_startup_coordinator.dart';
import 'package:neuro_companion/startup/neura_startup_turntable.dart';

class _ObservedBundle extends CachingAssetBundle {
  _ObservedBundle({this.missingAtlas = false, this.delayedAtlas});

  final bool missingAtlas;
  final Future<ByteData>? delayedAtlas;
  final loads = <String, int>{};

  @override
  Future<ByteData> load(String key) async {
    loads.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (key == kNeuraStartupTurntableAsset) {
      if (missingAtlas) throw StateError('Synthetic missing turntable');
      if (delayedAtlas != null) return delayedAtlas!;
    }
    return rootBundle.load(key);
  }
}

class _PendingBoot extends Fake implements NeuraStartupCoordinator {
  @override
  final ready = ValueNotifier(false);
  @override
  final booting = ValueNotifier(true);
  @override
  final stage = ValueNotifier(const NeuraBootStage('Synthetic boot', 0.5));
  @override
  final failure = ValueNotifier<NeuraBootFailure?>(null);
  @override
  Future<void> boot() async {}
}

Widget _host(
  _ObservedBundle bundle, {
  bool animate = true,
  bool reduceMotion = false,
  bool tickerEnabled = true,
  double pixelRatio = 1,
}) =>
    MaterialApp(
      home: DefaultAssetBundle(
        bundle: bundle,
        child: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduceMotion,
            devicePixelRatio: pixelRatio,
          ),
          child: TickerMode(
            enabled: tickerEnabled,
            child: Center(
              child: NeuraStartupAvatar(animate: animate, turnOnEntry: true),
            ),
          ),
        ),
      ),
    );

int _frame(WidgetTester tester) => tester
    .widget<NeuraStartupPortrait>(find.byType(NeuraStartupPortrait))
    .frame
    .value;

NeuraStartupTurntablePainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<NeuraStartupTurntablePainter>()
    .single;

Future<void> _decodeAtlas(WidgetTester tester, _ObservedBundle bundle) async {
  await tester.runAsync(() => precacheImage(
        ExactAssetImage(kNeuraStartupTurntableAsset, bundle: bundle),
        tester.element(find.byType(NeuraStartupAvatar)),
      ));
  await tester.pump();
  await tester.pump();
}

Future<_ObservedBundle> _start(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final bundle = _ObservedBundle();
  await tester.pumpWidget(_host(bundle));
  await _decodeAtlas(tester, bundle);
  return bundle;
}

void main() {
  testWidgets('real front, side and back frames stay within a 5 MiB atlas',
      (tester) async {
    final bundle = await _start(tester);
    final atlas = _painter(tester).atlas;
    expect(atlas.width, 1280);
    expect(atlas.height, 960);
    expect(atlas.width * atlas.height * 4, lessThan(5 * 1024 * 1024));
    final data = await tester.runAsync(
      () => atlas.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();
    int channel(int frame, int x, int y, int c) => bytes[
        (((frame ~/ 8) * 240 + y) * atlas.width + (frame % 8) * 160 + x) * 4 +
            c];
    var rearDifferences = 0;
    var sidePixels = 0;
    for (var y = 0; y < 240; y++) {
      for (var x = 0; x < 160; x++) {
        if (channel(8, x, y, 3) > 64) sidePixels++;
        if ((channel(16, x, y, 3) - channel(0, 159 - x, y, 3)).abs() > 64 ||
            (channel(16, x, y, 0) - channel(0, 159 - x, y, 0)).abs() > 32) {
          rearDifferences++;
        }
      }
    }
    expect(sidePixels, greaterThan(1500),
        reason: 'A profile must retain body thickness.');
    expect(rearDifferences, greaterThan(1500),
        reason: 'The rear must not be the mirrored front.');
    await tester.pumpWidget(_host(bundle, pixelRatio: 12));
    expect(_painter(tester).atlas.width, 1280);
    expect(bundle.loads[kNeuraStartupTurntableAsset], 1);
  });

  testWidgets('one 900 ms turn shows the rear halfway and then keeps breathing',
      (tester) async {
    final bundle = await _start(tester);
    final portrait =
        tester.widget<NeuraStartupPortrait>(find.byType(NeuraStartupPortrait));
    await tester.pump(const Duration(milliseconds: 225));
    expect(_frame(tester), inInclusiveRange(3, 5));
    await tester.pump(const Duration(milliseconds: 225));
    expect(_frame(tester), 16);
    final transform = tester
        .widget<Transform>(find
            .ancestor(
              of: find.byType(NeuraStartupPortrait),
              matching: find.byType(Transform),
            )
            .first)
        .transform;
    expect(transform.entry(0, 0), greaterThan(0));
    expect(transform.entry(2, 0), 0);
    await tester.pump(const Duration(milliseconds: 450));
    expect(_frame(tester), 0);
    await tester.pump(const Duration(seconds: 6));
    expect(_frame(tester), 0);
    expect(
        identical(
            tester.widget<NeuraStartupPortrait>(
                find.byType(NeuraStartupPortrait)),
            portrait),
        isTrue);
    expect(bundle.loads[kNeuraStartupTurntableAsset], 1);
  });

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('$state interrupts a real turn without replay', (tester) async {
      await _start(tester);
      await tester.pump(const Duration(milliseconds: 450));
      expect(_frame(tester), 16);
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pumpAndSettle();
      expect(_frame(tester), 0);
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(_frame(tester), 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion and covered routes reset without replay',
      (tester) async {
    final bundle = await _start(tester);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpWidget(_host(bundle, reduceMotion: true));
    await tester.pumpAndSettle();
    expect(_frame(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_host(bundle));
    await tester.pump(const Duration(milliseconds: 450));
    expect(_frame(tester), 0);
    await tester.pumpWidget(_host(bundle, tickerEnabled: false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a still startup loads only the front portrait', (tester) async {
    final bundle = _ObservedBundle();
    await tester.pumpWidget(_host(bundle, animate: false));
    await tester.pumpAndSettle();
    expect(bundle.loads[kNeuraStartupTurntableAsset], isNull);
    expect(_frame(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a missing atlas leaves the arms-down front visible',
      (tester) async {
    final bundle = _ObservedBundle(missingAtlas: true);
    await tester.pumpWidget(_host(bundle));
    await tester.runAsync(() => precacheImage(
          ExactAssetImage(kNeuraStartupTurntableAsset, bundle: bundle),
          tester.element(find.byType(NeuraStartupAvatar)),
          onError: (_, __) {},
        ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(_frame(tester), 0);
    final provider =
        tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect((provider.imageProvider as AssetImage).assetName,
        kNeuraStartupFrontAsset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an atlas arriving after interruption cannot start a late turn',
      (tester) async {
    final completion = Completer<ByteData>();
    final bundle = _ObservedBundle(delayedAtlas: completion.future);
    await tester.pumpWidget(_host(bundle));
    await tester.pump(const Duration(milliseconds: 200));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    completion.complete((await tester.runAsync(
      () => rootBundle.load(kNeuraStartupTurntableAsset),
    ))!);
    await _decodeAtlas(tester, bundle);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(_frame(tester), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'production Safe Mode cancels the startup turn and cannot replay it',
      (tester) async {
    final safeMode = SafeBoot.instance.safeMode;
    final originalSafe = safeMode.value;
    final originalRecovery = SafeBoot.instance.restartRequired.value;
    addTearDown(() {
      NeuraMotion.instance.stop();
      safeMode.value = originalSafe;
      SafeBoot.instance.restartRequired.value = originalRecovery;
    });
    SafeBoot.instance.restartRequired.value = false;
    safeMode.value = true;
    NeuraMotion.instance.start();
    final bundle = _ObservedBundle();
    final coordinator = _PendingBoot();
    await tester.pumpWidget(MaterialApp(
      home: DefaultAssetBundle(
        bundle: bundle,
        child:
            NeuraBootScreen(coordinator: coordinator, hasOwnerPassword: true),
      ),
    ));
    await tester.pump();
    expect(
        tester
            .widget<NeuraStartupAvatar>(find.byType(NeuraStartupAvatar))
            .animate,
        isFalse);
    expect(bundle.loads[kNeuraStartupTurntableAsset], isNull);
    safeMode.value = false;
    await tester.pump();
    await _decodeAtlas(tester, bundle);
    await tester.pump(const Duration(milliseconds: 450));
    expect(_frame(tester), 16);
    safeMode.value = true;
    await tester.pump();
    expect(_frame(tester), 0);
    safeMode.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(_frame(tester), 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
