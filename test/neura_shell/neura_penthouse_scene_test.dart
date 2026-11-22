import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_penthouse_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
