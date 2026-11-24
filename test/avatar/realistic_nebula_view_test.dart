import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/avatar_controller.dart';
import 'package:neuro_companion/avatar/avatar_globals.dart';
import 'package:neuro_companion/avatar/avatar_registry.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/avatar/renderers/nebula_avatar_view.dart';
import 'package:neuro_companion/avatar/renderers/neura_mouth_layer.dart';
import 'package:neuro_companion/avatar/renderers/realistic_nebula_view.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_room_presence_avatar.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/avatar_selector_screen.dart';
import 'package:neuro_companion/services/avatar_service.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MissingAtlas extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key == RealisticNebulaView.faceAsset) {
      return Future.error(FlutterError('Missing fixture atlas'));
    }
    return rootBundle.load(key);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const id = AvatarRegistry.realisticNebulaId;
  final service = AvatarService.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    await NeuraPrefsCache.prefs.clear();
    service.resetForTesting();
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    NeuraMotion.instance.stop();
    SafeBoot.instance.safeMode.value = false;
    AvatarGlobals.controller.setTalking(false);
    AvatarGlobals.controller.setNumberInput('mouthOpen', 0);
    AvatarGlobals.controller.setNumberInput('viseme', 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    service.resetForTesting();
  });

  // Decode the actual packaged files in real time. Widget pumps otherwise run
  // on a fake clock, whereas the engine decodes the WebPs asynchronously.
  Future<void> warmAssets(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(ScaffoldMessenger));
    await tester.runAsync(() async {
      for (final provider in <ImageProvider>[
        const ExactAssetImage(RealisticNebulaView.faceAsset),
        for (final h in [144, 384, 768, 1344])
          ResizeImage.resizeIfNeeded(
              null, h, const AssetImage(RealisticNebulaView.bodyAsset)),
      ]) {
        await precacheImage(provider, context,
            onError: (e, _) => fail('Could not decode local art: $e'));
      }
    });
    await tester.pump();
  }

  RealisticMouthPainter mouth(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<RealisticMouthPainter>()
      .single;

  testWidgets('fitted portrait shows hands and overlays speech on its lips',
      (tester) async {
    await warmAssets(tester);
    final c = AvatarController();
    addTearDown(c.dispose);
    const capture = ValueKey('portrait capture');
    const size = 384.0;
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
      key: capture,
      child: RealisticNebulaView(size: size, controller: c, enabled: true),
    ))));
    await tester.pump();
    final box = tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
    Future<ByteData> pixels() async => (await tester.runAsync(() async {
          final image = await box.toImage();
          try {
            return (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba))!;
          } finally {
            image.dispose();
          }
        }))!;
    int index(int bodyX, int bodyY) {
      const scale = size / 1536;
      final x = ((size - 1024 * scale) / 2 + bodyX * scale).floor();
      return ((bodyY * scale).floor() * size.toInt() + x) * 4;
    }

    final rest = await pixels();
    for (final x in [310, 710]) {
      expect(rest.getUint8(index(x, 838) + 3), greaterThan(210));
    }
    for (final x in [145, 880]) {
      expect(rest.getUint8(index(x, 320) + 3), 0);
    }
    expect(rest.getUint8(index(500, 234) + 3), greaterThan(220));
    c.setTalking(true);
    c.setNumberInput('viseme', NeuraViseme.O.index.toDouble());
    c.setNumberInput('mouthOpen', 1);
    await tester.pump();
    final talking = await pixels();
    expect(talking.getUint32(index(500, 234)),
        isNot(rest.getUint32(index(500, 234))));
    expect(talking.getUint32(index(500, 414)), rest.getUint32(index(500, 414)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('picker saves and reopens both appearances', (tester) async {
    await warmAssets(tester);
    await tester.pumpWidget(const MaterialApp(home: AvatarSelectorScreen()));
    await tester.pumpAndSettle();
    for (final selection in [id, AvatarRegistry.nebulaId]) {
      final row = find.byKey(ValueKey(selection));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(service.selectedAvatarId.value, selection);
      final reopened = AvatarService.forTesting();
      expect((await reopened.getSelectedAvatar()).id, selection);
      reopened.selectedAvatarId.dispose();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'local face shows distinct speech shapes and cancels at motion boundaries',
      (tester) async {
    await warmAssets(tester);
    final c = AvatarController();
    addTearDown(c.dispose);
    Widget host({bool reduced = false, bool enabled = true}) => MaterialApp(
          home: MediaQuery(
            data:
                MediaQueryData(disableAnimations: reduced, devicePixelRatio: 1),
            child: Center(
                child: RealisticNebulaView(
                    controller: c, size: 192, enabled: enabled)),
          ),
        );
    await tester.pumpWidget(host());
    await tester.pump();
    expect(mouth(tester).tile, 0);
    c.setTalking(true);
    expect(mouth(tester).pose, NeuraMouthPose.rest);
    c.setNumberInput('mouthOpen', .25);
    c.setNumberInput('viseme', NeuraViseme.AI.index.toDouble(),
        isStartHint: true);
    await tester.pump();
    expect(mouth(tester).tile, 0);
    c.setNumberInput('mouthOpen', .8);
    for (final entry in {
      NeuraViseme.MBP: 1,
      NeuraViseme.O: 2,
      NeuraViseme.AI: 3,
      NeuraViseme.FV: 4
    }.entries) {
      c.setNumberInput('viseme', entry.key.index.toDouble());
      await tester.pump();
      expect(mouth(tester).tile, entry.value);
    }
    bool blinking() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((w) => w.foregroundPainter != null && w.child is RawImage);
    c.pulseBlink();
    await tester.pump();
    expect(blinking(), isTrue);
    await tester.pumpWidget(host(reduced: true));
    expect(blinking(), isFalse);
    expect(mouth(tester).tile, 0);
    await tester.pumpWidget(host());
    c.setNumberInput('mouthOpen', 1);
    await tester.pump();
    expect(mouth(tester).tile, 0);
    c.setTalking(false);
    c.setTalking(true);
    await tester.pump();
    expect(mouth(tester).tile, 0);
    c.setNumberInput('viseme', NeuraViseme.FV.index.toDouble());
    await tester.pump();
    expect(mouth(tester).tile, 4);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(mouth(tester).tile, 0);
    // Flutter suspends frames while paused. The first resumed frame must rest.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    c.setNumberInput('mouthOpen', .9);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(mouth(tester).tile, 0);
    await tester.pumpWidget(host(enabled: false));
    c.pulseBlink();
    await tester.pump();
    expect(blinking(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'room holds the selected portrait through Safe Mode without replay',
      (tester) async {
    await warmAssets(tester);
    expect(await service.selectAvatar(id), isTrue);
    NeuraMotion.instance.start();
    Widget room(NeuraPresencePhase phase) => MaterialApp(
            home: Center(
          child: SizedBox.square(
              dimension: 168,
              child: NeuraRoomPresenceAvatar(
                room: NeuraRoom.penthouse,
                phase: phase,
                motion: NeuraCompanionMotion.subtle,
                scale: NeuraCompanionScale.standard,
              )),
        ));
    await tester.pumpWidget(room(NeuraPresencePhase.idle));
    await tester.pump();
    final c = AvatarGlobals.controller;
    void speak() {
      c.setTalking(false);
      c.setTalking(true);
      c.setNumberInput('viseme', NeuraViseme.AI.index.toDouble());
      c.setNumberInput('mouthOpen', .8);
    }

    speak();
    await tester.pump();
    expect(mouth(tester).tile, 3);
    SafeBoot.instance.safeMode.value = true;
    await tester.pumpWidget(room(NeuraPresencePhase.safeMode));
    await tester.pump();
    final safe =
        tester.widget<RealisticNebulaView>(find.byType(RealisticNebulaView));
    expect(safe.enabled, isFalse);
    expect(identical(safe.controller, c), isFalse);
    expect(mouth(tester).tile, 0);
    SafeBoot.instance.safeMode.value = false;
    await tester.pumpWidget(room(NeuraPresencePhase.idle));
    await tester.pump();
    expect(mouth(tester).tile, 0);
    speak();
    await tester.pump();
    expect(mouth(tester).tile, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing local atlas falls back to the drawn resting Nebula',
      (tester) async {
    final c = AvatarController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
        home: DefaultAssetBundle(
      bundle: _MissingAtlas(),
      child: RealisticNebulaView(controller: c, size: 128, enabled: false),
    )));
    await tester.pump();
    final fallback =
        tester.widget<NebulaAvatarView>(find.byType(NebulaAvatarView));
    expect(fallback.enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
