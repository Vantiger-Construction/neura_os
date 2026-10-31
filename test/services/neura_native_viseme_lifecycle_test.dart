import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/neura_event_bus.dart';
import 'package:neuro_companion/core/neura_events.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';
import 'package:neuro_companion/integrations/tts/neura_windows_tts.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/speech_synthesis');
  late NeuraWindowsTts native;
  late NeuraTtsService service;
  final events = <Object>[];
  Completer<Object?>? acknowledgement;
  Completer<Object?>? pendingPoll;
  Completer<Object?>? stop;
  var id = 0;

  void record(Object event) => events.add(event);
  bool activates(Object e) =>
      (e is NeuraTalkingEvent && e.isTalking) ||
      (e is NeuraMouthOpenEvent && e.open > 0) ||
      (e is NeuraVisemeEvent && e.viseme != NeuraViseme.rest);

  void speechTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        for (final gate in [acknowledgement, stop]) {
          if (gate != null && !gate.isCompleted) gate.complete(1);
        }
        if (pendingPoll != null && !pendingPoll!.isCompleted) {
          pendingPoll!.complete({'id': id, 'state': 'cancelled'});
        }
        stop = null;
        final ending = service.dispose();
        await tester.pump();
        await ending;
      }
    });
  }

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    acknowledgement = pendingPoll = stop = null;
    id = 0;
    events.clear();
    native = NeuraWindowsTts(pollInterval: const Duration(milliseconds: 10));
    service = NeuraTtsService.forTesting(native);
    NeuraEventBus.I.onAny(record);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'getVoices') return <dynamic>[];
      if (call.method == 'speak') {
        id = (call.arguments as Map)['id'] as int;
        if (acknowledgement != null) return acknowledgement!.future;
      }
      if (call.method == 'stop' && stop != null) return stop!.future;
      if (call.method == 'poll') {
        if (pendingPoll != null) return pendingPoll!.future;
        return {'id': id, 'state': 'speaking', 'viseme': 3};
      }
      return 1;
    });
  });

  tearDown(() async {
    for (final gate in [acknowledgement, stop]) {
      if (gate != null && !gate.isCompleted) gate.complete(1);
    }
    if (pendingPoll != null && !pendingPoll!.isCompleted) {
      pendingPoll!.complete({'id': id, 'state': 'cancelled'});
    }
    stop = null;
    NeuraEventBus.I.offAny(record);
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final boundary in ['stop', 'safe mode', 'background', 'dispose']) {
    speechTest(
      '$boundary revokes a pending native start before its acknowledgement',
      (tester) async {
        acknowledgement = Completer<Object?>();
        final speech = service.speak('Synthetic private speech.');
        await tester.pump();
        expect(id, 1);
        Future<void>? ending;
        switch (boundary) {
          case 'stop':
            ending = service.stop();
          case 'safe mode':
            SafeBoot.instance.safeMode.value = true;
          case 'background':
            binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          case 'dispose':
            ending = service.dispose();
        }
        events.clear();
        acknowledgement!.complete(1);
        await tester.pump();
        expect(events.where(activates), isEmpty);
        if (ending != null) await ending;
        await speech;
      },
    );
  }

  speechTest(
    'stop closes animation immediately while native purge is pending',
    (tester) async {
      final speech = service.speak('Synthetic speech.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(events.whereType<NeuraMouthOpenEvent>().last.open, greaterThan(0));
      stop = Completer<Object?>();
      final stopping = service.stop();
      expect(events.whereType<NeuraTalkingEvent>().last.isTalking, isFalse);
      expect(
        events.whereType<NeuraVisemeEvent>().last.viseme,
        NeuraViseme.rest,
      );
      stop!.complete(1);
      await tester.pump();
      await stopping;
      await speech;
    },
  );

  speechTest(
    'late poll from a cancelled stream cannot animate its replacement',
    (tester) async {
      final first = service.speak('Synthetic first.');
      await tester.pump();
      pendingPoll = Completer<Object?>();
      await tester.pump(const Duration(milliseconds: 10));
      final old = pendingPoll!;
      final stopping = service.stop();
      await tester.pump();
      await stopping;
      await first;
      final second = service.speak('Synthetic replacement.');
      await tester.pump();
      events.clear();
      pendingPoll = null;
      old.complete({'id': 1, 'state': 'speaking', 'viseme': 3});
      await tester.pump();
      expect(events.where(activates), isEmpty);
      await tester.pump(const Duration(milliseconds: 10));
      expect(events.whereType<NeuraMouthOpenEvent>().last.open, greaterThan(0));
      final ending = service.stop();
      await tester.pump();
      await ending;
      await second;
    },
  );

  speechTest('foreground recovery requires a fresh speech request', (
    tester,
  ) async {
    final first = service.speak('Synthetic first.');
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await first;
    events.clear();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(events.where(activates), isEmpty);
    final second = service.speak('Synthetic new request.');
    await tester.pump();
    expect(events.where(activates), isNotEmpty);
    final ending = service.stop();
    await tester.pump();
    await ending;
    await second;
  });

  speechTest(
      'Windows ignores text progress and error presence withholds private details',
      (tester) async {
    final speech = service.speak('Synthetic private transcript.');
    final failure = expectLater(speech, throwsStateError);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    events.clear();
    native.progressHandler
        ?.call('Synthetic private transcript.', 0, 9, 'Synthetic');
    expect(events, isEmpty, reason: 'Windows must use owned SAPI visemes only');
    native.errorHandler
        ?.call('Synthetic private transcript and persistent note');
    await tester.pump();
    await failure;
    final error = events.whereType<NeuraErrorEvent>().single;
    expect(error.error, 'Local speech failed.');
    expect(error.stack, isNull);
    expect(events.whereType<NeuraMouthOpenEvent>().last.open, 0);
    events.clear();
    native.visemeHandler?.call(3);
    native.progressHandler
        ?.call('Synthetic private transcript.', 0, 9, 'Synthetic');
    expect(events, isEmpty);
  });
}
