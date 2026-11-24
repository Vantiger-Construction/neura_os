import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_penthouse_scene.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() {
    NeuraMotion.instance.stop();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(NeuraMotion.instance.stop);

  ui.Picture record(NeuraRoom room, Size size, {bool furniture = true}) {
    final recorder = ui.PictureRecorder();
    final painter = NeuraPenthousePainter(
      room: room,
      overlay: Colors.transparent,
      showFurniture: furniture,
    );
    painter.paint(Canvas(recorder), size);
    return recorder.endRecording();
  }

  Future<Uint8List> pixels(NeuraRoom room) async {
    final picture = record(room, const Size(160, 120));
    final image = picture.toImageSync(160, 120);
    final data = await image.toByteData();
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }

  bool sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  test('every room paints at small, wide and tall sizes', () {
    const sizes = <Size>[
      Size.zero,
      Size(1, 1),
      Size(48, 48),
      Size(1280, 800),
      Size(400, 860),
    ];
    for (final room in NeuraRoom.all) {
      for (final size in sizes) {
        for (final furniture in <bool>[true, false]) {
          record(room, size, furniture: furniture).dispose();
        }
      }
    }
  });

  test('each room has its own look', () async {
    final looks = <String, Uint8List>{
      for (final room in NeuraRoom.all) room.id: await pixels(room),
    };
    final ids = looks.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final same = sameBytes(looks[ids[i]]!, looks[ids[j]]!);
        expect(same, isFalse, reason: '${ids[i]} and ${ids[j]} match');
      }
    }
  });

  test('the penthouse is the default and a room change repaints', () {
    final penthouse = NeuraPenthousePainter(
      overlay: Colors.transparent,
      showFurniture: true,
    );
    expect(penthouse.room.id, NeuraRoom.penthouse.id);
    final same = NeuraPenthousePainter(
      room: NeuraRoom.penthouse,
      overlay: Colors.transparent,
      showFurniture: true,
    );
    final suite = NeuraPenthousePainter(
      room: NeuraRoom.herSuite,
      overlay: Colors.transparent,
      showFurniture: true,
    );
    expect(same.shouldRepaint(penthouse), isFalse);
    expect(suite.shouldRepaint(penthouse), isTrue);
  });

  testWidgets('the scene stays still and schedules no frames', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NeuraPenthouseScene(room: NeuraRoom.dreamAtrium),
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  Widget scene(NeuraRoom room, {bool reduceMotion = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: NeuraPenthouseScene(room: room),
      ),
    );
  }

  List<String> paintedRooms(WidgetTester tester) {
    return tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<NeuraPenthousePainter>()
        .map((painter) => painter.room.id)
        .toList();
  }

  double opacityOf(WidgetTester tester, String roomId) {
    final paint = find.byWidgetPredicate((widget) {
      final painter = widget is CustomPaint ? widget.painter : null;
      return painter is NeuraPenthousePainter && painter.room.id == roomId;
    });
    final fades = find.byType(FadeTransition);
    final fade = find.ancestor(of: paint, matching: fades);
    return tester.widget<FadeTransition>(fade.first).opacity.value;
  }

  testWidgets('with motion live, one room fades into the next', (
    tester,
  ) async {
    NeuraMotion.instance.start();
    await tester.pumpWidget(scene(NeuraRoom.penthouse));
    await tester.pumpWidget(scene(NeuraRoom.moodDen));
    await tester.pump(const Duration(milliseconds: 300));
    final fading = paintedRooms(tester);
    expect(fading, containsAll(<String>['penthouse', 'mood_den']));
    final leaving = opacityOf(tester, 'penthouse');
    final arriving = opacityOf(tester, 'mood_den');
    expect(leaving, inExclusiveRange(0, 1));
    expect(arriving, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(opacityOf(tester, 'penthouse'), lessThan(leaving));
    expect(opacityOf(tester, 'mood_den'), greaterThan(arriving));
    await tester.pump(NeuraPenthouseScene.crossfade);
    expect(paintedRooms(tester), <String>['mood_den']);
  });

  testWidgets('without live motion the room changes at once', (tester) async {
    await tester.pumpWidget(scene(NeuraRoom.penthouse));
    await tester.pumpWidget(scene(NeuraRoom.joyLounge));
    await tester.pump();
    expect(paintedRooms(tester), <String>['joy_lounge']);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion changes the room at once', (tester) async {
    NeuraMotion.instance.start();
    await tester.pumpWidget(scene(NeuraRoom.penthouse, reduceMotion: true));
    await tester.pumpWidget(scene(NeuraRoom.herSuite, reduceMotion: true));
    await tester.pump();
    expect(paintedRooms(tester), <String>['her_suite']);
  });
}
