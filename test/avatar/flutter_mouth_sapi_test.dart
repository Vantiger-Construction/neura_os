import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/avatar_controller.dart';
import 'package:neuro_companion/avatar/avatar_orchestrator.dart';
import 'package:neuro_companion/avatar/avatar_orchestrator_viseme_ext.dart';
import 'package:neuro_companion/avatar/renderers/flutter_mouth_avatar_view.dart';
import 'package:neuro_companion/avatar/renderers/neura_mouth_layer.dart';
import 'package:neuro_companion/avatar/viseme/sapi_viseme_map.dart';
import 'package:neuro_companion/core/neura_event_bus.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';
import 'package:neuro_companion/integrations/tts/neura_windows_tts.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/screens/neura_speech_prototype_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/speech_synthesis');
  const pictureKey = ValueKey('rendered-speech-prototype');
  late AvatarController controller;
  late AvatarOrchestrator orchestrator;
  late AvatarVisemeWiring wiring;
  late NeuraWindowsTts native;
  late NeuraTtsService speech;
  var id = 0;
  var viseme = 0;
  var state = 'speaking';
  Completer<Object?>? pendingPoll;
  Completer<Object?>? pendingStart;
  Completer<Object?>? pendingStop;

  NeuraMouthPose pose(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<NeuraMouthPainter>()
      .single
      .pose;

  Widget host(
          {bool tickers = true,
          bool reduced = false,
          AvatarController? selected}) =>
      MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
            enabled: tickers,
            child: Center(
              child: RepaintBoundary(
                  key: pictureKey,
                  child: FlutterMouthAvatarView(
                    controller: selected ?? controller,
                    size: 200,
                  )),
            )),
      ));

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.byType(FlutterMouthAvatarView), findsOneWidget);
  }

  Future<void> poll(WidgetTester tester, int value) async {
    viseme = value;
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
  }

  Future<Uint8List> pixels(WidgetTester tester) async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(pictureKey));
    return (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
  }

  void speechTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        for (final gate in [pendingStart, pendingStop]) {
          if (gate != null && !gate.isCompleted) gate.complete(1);
        }
        if (pendingPoll != null && !pendingPoll!.isCompleted) {
          pendingPoll!.complete({'id': id, 'state': 'cancelled'});
        }
        pendingStop = null;
        final ending = speech.dispose();
        await tester.pump();
        await ending;
        await tester.pumpWidget(const SizedBox.shrink());
        wiring.stop();
        orchestrator.dispose();
        controller.dispose();
      }
    });
  }

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    id = viseme = 0;
    state = 'speaking';
    pendingPoll = pendingStart = pendingStop = null;
    controller = AvatarController();
    orchestrator =
        AvatarOrchestrator(controller: controller, bus: NeuraEventBus.I)
          ..start();
    wiring = AvatarVisemeWiring(controller: controller, bus: NeuraEventBus.I)
      ..start();
    native = NeuraWindowsTts(pollInterval: const Duration(milliseconds: 10));
    speech = NeuraTtsService.forTesting(native);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      if (call.method == 'speak') {
        id = (call.arguments as Map)['id'] as int;
        if (pendingStart != null) return pendingStart!.future;
      }
      if (call.method == 'stop' && pendingStop != null) {
        return pendingStop!.future;
      }
      if (call.method == 'poll') {
        if (pendingPoll != null) return pendingPoll!.future;
        return {'id': id, 'state': state, 'viseme': viseme};
      }
      return 1;
    });
  });

  tearDown(() {
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  speechTest(
      'actual native-channel visemes change painted pixels; silence and bilabials close',
      (tester) async {
    await mount(tester);
    final resting = await pixels(tester);
    await expectLater(
        find.byKey(pictureKey), matchesGoldenFile('goldens/mouth_rest.png'));
    final speaking = speech.speak('Synthetic local speech.');
    await tester.pump();
    expect(pose(tester), NeuraMouthPose.rest,
        reason: 'An acknowledgement is not a phoneme');
    await poll(tester, 2);
    expect(pose(tester).viseme, NeuraViseme.AI);
    expect(pose(tester).open, 0.6);
    final open = await pixels(tester);
    expect(open, isNot(orderedEquals(resting)));
    await expectLater(
        find.byKey(pictureKey), matchesGoldenFile('goldens/mouth_ai.png'));
    await poll(tester, 7);
    expect(await pixels(tester), isNot(orderedEquals(open)));
    await expectLater(
        find.byKey(pictureKey), matchesGoldenFile('goldens/mouth_wq.png'));
    await poll(tester, 21);
    expect(pose(tester).viseme, NeuraViseme.MBP);
    expect(pose(tester).open, 0);
    await expectLater(
        find.byKey(pictureKey), matchesGoldenFile('goldens/mouth_mbp.png'));
    await poll(tester, 0);
    expect(await pixels(tester), orderedEquals(resting));
    state = 'completed';
    await poll(tester, 0);
    await speaking;
    expect(pose(tester), NeuraMouthPose.rest);
    expect(await pixels(tester), orderedEquals(resting));
  });

  for (final terminal in ['completed', 'cancelled', 'failed']) {
    speechTest(
        '$terminal closes the rendered mouth and rejects stale callbacks',
        (tester) async {
      await mount(tester);
      final resting = await pixels(tester);
      final speaking = speech.speak('Synthetic local speech.');
      final outcome = terminal == 'failed'
          ? expectLater(speaking, throwsStateError)
          : speaking;
      await tester.pump();
      await poll(tester, 2);
      expect(pose(tester).open, greaterThan(0));
      state = terminal;
      await poll(tester, 2);
      await outcome;
      native.visemeHandler?.call(2);
      await tester.pump();
      expect(pose(tester), NeuraMouthPose.rest);
      expect(await pixels(tester), orderedEquals(resting));
    });
  }

  speechTest(
      'prototype preview requires a tap, supports interruption and stops on exit',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: NeuraSpeechPrototypeScreen(
      controller: controller,
      speech: speech,
    )));
    await tester.pump();
    expect(find.byType(FlutterMouthAvatarView), findsOneWidget);
    expect(id, 0);
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    SafeBoot.instance.safeMode.value = false;
    await tester.pump();
    await tester.tap(find.text('Play local sample'));
    await tester.pump();
    expect(id, 1);
    await poll(tester, 2);
    expect(pose(tester).open, 0.6);
    await tester.tap(find.text('Speak again'));
    await tester.pump();
    await tester.pump();
    expect(id, 2);
    await poll(tester, 7);
    expect(pose(tester).viseme, NeuraViseme.WQ);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump();
    expect(pose(tester), NeuraMouthPose.rest);
    await tester.tap(find.text('Play local sample'));
    await tester.pump();
    await poll(tester, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    native.visemeHandler?.call(2);
    await tester.pump();
    expect(controller.signals.isTalking, isFalse);
    expect(controller.numberInput('mouthOpen'), 0);
    expect(tester.takeException(), isNull);
  });

  speechTest('all 22 native shapes reach the visible layer with bounded poses',
      (tester) async {
    await mount(tester);
    final speaking = speech.speak('Synthetic local speech.');
    await tester.pump();
    for (var value = 0; value <= NeuraSapiVisemes.maxId; value++) {
      await poll(tester, value);
      expect(pose(tester).viseme, NeuraSapiVisemes.viseme(value));
      expect(pose(tester).open, NeuraSapiVisemes.mouthOpen(value));
      expect(pose(tester).open, inInclusiveRange(0, 1));
    }
    state = 'completed';
    await poll(tester, 0);
    await speaking;
    expect(pose(tester), NeuraMouthPose.rest);
  });

  speechTest('non-Windows production preview never starts a platform voice',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(MaterialApp(
          home: NeuraSpeechPrototypeScreen(
        controller: controller,
      )));
      await tester.pump();
      expect(find.text('Available on Windows'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(id, 0);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  for (final boundary in ['stop', 'safe mode', 'background', 'dispose']) {
    speechTest(
        '$boundary closes pixels before native purge; late polls cannot reopen them',
        (tester) async {
      await mount(tester);
      final resting = await pixels(tester);
      final speaking = speech.speak('Synthetic local speech.');
      await tester.pump();
      await poll(tester, 2);
      pendingPoll = Completer<Object?>();
      await tester.pump(const Duration(milliseconds: 10));
      pendingStop = Completer<Object?>();
      Future<void>? ending;
      switch (boundary) {
        case 'stop':
          ending = speech.stop();
        case 'safe mode':
          SafeBoot.instance.safeMode.value = true;
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        case 'dispose':
          ending = speech.dispose();
      }
      await tester.pump();
      await tester.pump(); // Bus delivery precedes the frame that paints rest.
      expect(pose(tester), NeuraMouthPose.rest);
      expect(await pixels(tester), orderedEquals(resting));
      SafeBoot.instance.safeMode.value = false;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      pendingPoll!.complete({'id': id, 'state': 'speaking', 'viseme': 2});
      pendingPoll = null;
      native.visemeHandler?.call(2);
      await tester.pump();
      expect(await pixels(tester), orderedEquals(resting));
      pendingStop!.complete(1);
      await tester.pump();
      if (ending != null) await ending;
      await speaking;
    });

    speechTest(
        '$boundary rejects delayed native start without visible movement',
        (tester) async {
      await mount(tester);
      final resting = await pixels(tester);
      pendingStart = Completer<Object?>();
      final speaking = speech.speak('Synthetic local speech.');
      await tester.pump();
      Future<void>? ending;
      switch (boundary) {
        case 'stop':
          ending = speech.stop();
        case 'safe mode':
          SafeBoot.instance.safeMode.value = true;
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        case 'dispose':
          ending = speech.dispose();
      }
      pendingStart!.complete(1);
      await tester.pump();
      if (ending != null) await ending;
      await speaking;
      expect(await pixels(tester), orderedEquals(resting));
    });
  }

  speechTest('interruption isolates an old poll from the replacement mouth',
      (tester) async {
    await mount(tester);
    final first = speech.speak('Synthetic first.');
    await tester.pump();
    await poll(tester, 2);
    pendingPoll = Completer<Object?>();
    await tester.pump(const Duration(milliseconds: 10));
    final old = pendingPoll!;
    final second = speech.speak('Synthetic replacement.');
    await tester.pump();
    await first;
    await tester.pump();
    expect(pose(tester), NeuraMouthPose.rest);
    pendingPoll = null;
    old.complete({'id': 1, 'state': 'speaking', 'viseme': 2});
    await tester.pump();
    expect(pose(tester), NeuraMouthPose.rest);
    await poll(tester, 21);
    expect(pose(tester).viseme, NeuraViseme.MBP);
    await poll(tester, 3);
    expect(pose(tester).viseme, NeuraViseme.O);
    state = 'completed';
    await poll(tester, 0);
    await second;
  });

  for (final boundary in [
    'ticker',
    'reduced motion',
    'background',
    'safe mode'
  ]) {
    speechTest(
        'renderer independently rests for $boundary and requires a fresh start',
        (tester) async {
      await mount(tester);
      controller.setTalking(true);
      controller.setNumberInput('viseme', NeuraViseme.AI.index.toDouble());
      controller.setNumberInput('mouthOpen', 0.6);
      await tester.pump();
      expect(pose(tester).open, 0.6);
      switch (boundary) {
        case 'ticker':
          await tester.pumpWidget(host(tickers: false));
        case 'reduced motion':
          await tester.pumpWidget(host(reduced: true));
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        case 'safe mode':
          SafeBoot.instance.safeMode.value = true;
      }
      await tester.pump();
      expect(pose(tester), NeuraMouthPose.rest);
      SafeBoot.instance.safeMode.value = false;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(host());
      controller.setNumberInput('mouthOpen', 0.8);
      await tester.pump();
      expect(pose(tester), NeuraMouthPose.rest);
      controller.setTalking(false);
      controller.setTalking(true);
      await tester.pump();
      expect(pose(tester).open, 0.8);
    });
  }

  speechTest(
      'controller replacement and renderer disposal detach listeners and discard cached poses',
      (tester) async {
    await mount(tester);
    controller.setTalking(true);
    controller.setNumberInput('viseme', NeuraViseme.AI.index.toDouble());
    controller.setNumberInput('mouthOpen', 0.6);
    await tester.pump();
    final replacement = AvatarController();
    await tester.pumpWidget(host(selected: replacement));
    controller.setNumberInput('mouthOpen', 0.9);
    await tester.pump();
    expect(pose(tester), NeuraMouthPose.rest);
    await tester.pumpWidget(const SizedBox.shrink());
    replacement.setTalking(true);
    replacement.setNumberInput('mouthOpen', 0.9);
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    SafeBoot.instance.safeMode.value = false;
    await tester.pumpWidget(host(selected: replacement));
    await tester.pump();
    expect(pose(tester), NeuraMouthPose.rest);
    await tester.pumpWidget(const SizedBox.shrink());
    replacement.dispose();
  });

  test('mouth contract rejects malformed inputs and enforces sealed bilabials',
      () {
    for (final bad in [double.nan, double.infinity, -1.0, 999.0, 1.5]) {
      expect(NeuraMouthPose.fromInputs(bad, 0.5), NeuraMouthPose.rest);
    }
    expect(NeuraMouthPose.fromInputs(1, double.nan), NeuraMouthPose.rest);
    expect(NeuraMouthPose.fromInputs(1, 9).open, 1);
    expect(NeuraMouthPose.fromInputs(1, -9).open, 0);
    expect(
        NeuraMouthPose.fromInputs(NeuraViseme.MBP.index.toDouble(), 1).open, 0);
    expect(NeuraMouthPose.fromInputs(0, 1), NeuraMouthPose.rest);
    expect(
        const NeuraMouthPainter(NeuraMouthPose.rest)
            .shouldRepaint(const NeuraMouthPainter(NeuraMouthPose.rest)),
        isFalse);
  });
}
