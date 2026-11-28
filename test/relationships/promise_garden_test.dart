import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_penthouse_scene.dart';
import 'package:neuro_companion/relationships/models/neura_promise.dart';
import 'package:neuro_companion/relationships/services/promise_garden.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

NeuraPromise _promise(int i, PromiseStatus status) => NeuraPromise(
      id: 'p$i',
      description: 'Promise $i',
      createdAt: DateTime(2026, 11, 1),
      status: status,
    );

List<NeuraPromise> _kept(int count, {int dropped = 0, int pending = 0}) => [
      for (var i = 0; i < count; i++) _promise(i, PromiseStatus.completed),
      for (var i = 0; i < dropped; i++)
        _promise(100 + i, PromiseStatus.dropped),
      for (var i = 0; i < pending; i++)
        _promise(200 + i, PromiseStatus.pending),
    ];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.clear();
    PromiseGardenService.instance.reset();
  });

  test('kept promises grow the plant through each stage', () {
    expect(PromiseGardenStage.forKeptCount(0), PromiseGardenStage.empty);
    expect(PromiseGardenStage.forKeptCount(1), PromiseGardenStage.seed);
    expect(PromiseGardenStage.forKeptCount(3), PromiseGardenStage.sprout);
    expect(PromiseGardenStage.forKeptCount(6), PromiseGardenStage.sprout);
    expect(PromiseGardenStage.forKeptCount(7), PromiseGardenStage.leafy);
    expect(PromiseGardenStage.forKeptCount(15), PromiseGardenStage.blooming);
    expect(PromiseGardenStage.forKeptCount(500), PromiseGardenStage.blooming);
  });

  test('dropped and open promises never shrink the plant', () {
    expect(PromiseGardenStage.from(_kept(3)), PromiseGardenStage.sprout);
    expect(
      PromiseGardenStage.from(_kept(3, dropped: 20, pending: 9)),
      PromiseGardenStage.sprout,
    );
    expect(
      PromiseGardenStage.from(_kept(0, dropped: 5)),
      PromiseGardenStage.empty,
    );
  });

  test('says how many promises the next stage needs', () {
    expect(PromiseGardenStage.toNextStage(0), 1);
    expect(PromiseGardenStage.toNextStage(4), 3);
    expect(PromiseGardenStage.toNextStage(15), isNull);
  });

  test('the service follows the promise list and a wipe empties it', () async {
    final garden = PromiseGardenService.instance;
    await garden.refresh(load: () async => _kept(7));
    expect(garden.stage.value, PromiseGardenStage.leafy);

    garden.reset();
    expect(garden.stage.value, PromiseGardenStage.empty);
  });

  test('an unreadable promise list leaves the plant as it was', () async {
    final garden = PromiseGardenService.instance;
    await garden.refresh(load: () async => _kept(3));
    await garden.refresh(load: () async => throw StateError('unreadable'));
    expect(garden.stage.value, PromiseGardenStage.sprout);
  });

  test('a refresh that finishes after a wipe cannot bring the plant back',
      () async {
    final garden = PromiseGardenService.instance;
    final pending = garden.refresh(load: () async {
      await Future<void>.delayed(Duration.zero);
      return _kept(15);
    });
    garden.reset();
    await pending;
    expect(garden.stage.value, PromiseGardenStage.empty);
  });

  test('every stage paints, and a new stage repaints the lounge', () {
    NeuraPenthousePainter painter(PromiseGardenStage stage) =>
        NeuraPenthousePainter(
          room: NeuraRoom.penthouse,
          overlay: Colors.transparent,
          showFurniture: true,
          garden: stage,
        );
    const sizes = <Size>[
      Size.zero,
      Size(1, 1),
      Size(1280, 800),
      Size(400, 860),
    ];
    for (final stage in PromiseGardenStage.values) {
      for (final size in sizes) {
        final recorder = ui.PictureRecorder();
        painter(stage).paint(Canvas(recorder), size);
        recorder.endRecording().dispose();
      }
    }
    expect(
      painter(PromiseGardenStage.leafy)
          .shouldRepaint(painter(PromiseGardenStage.sprout)),
      isTrue,
    );
    expect(
      painter(PromiseGardenStage.leafy)
          .shouldRepaint(painter(PromiseGardenStage.leafy)),
      isFalse,
    );
  });

  test('a new completion refresh wins over an older pending refresh', () async {
    final garden = PromiseGardenService.instance;
    final previous = Completer<List<NeuraPromise>>();
    final old = garden.refresh(load: () => previous.future);
    await garden.refresh(load: () async => _kept(7));
    previous.complete(_kept(0));
    await old;
    expect(garden.stage.value, PromiseGardenStage.leafy);
  });
}
