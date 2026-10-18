import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/integrations/tts/neura_windows_tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/speech_synthesis');

  void speechTest(
      String name,
      Future<void> Function(WidgetTester, NeuraWindowsTts, List<MethodCall>,
              void Function(Future<Object?> Function(MethodCall)))
          body) {
    testWidgets(name, (tester) async {
      final calls = <MethodCall>[];
      Future<Object?> Function(MethodCall) handler = (call) async => 1;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) {
        calls.add(call);
        return handler(call);
      });
      // Any accidental fallback to the old plugin is an explicit test failure.
      const legacy = MethodChannel('flutter_tts');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(legacy,
          (call) async {
        fail('Windows speech must not call flutter_tts: ${call.method}');
      });
      final tts = NeuraWindowsTts(
        commandTimeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 10),
      );
      try {
        await body(tester, tts, calls, (next) => handler = next);
      } finally {
        handler = (call) async => 1;
        await tts.stop().catchError((Object _) => 0);
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(legacy, null);
      }
    });
  }

  speechTest('Windows completion is tagged and carries no text',
      (tester, tts, calls, respond) async {
    var completions = 0;
    tts.setCompletionHandler(() => completions++);
    respond((call) async =>
        call.method == 'poll' ? {'id': 1, 'state': 'completed'} : 1);
    expect(await tts.speak('Synthetic alpha.'), 1);
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 10));
    expect(completions, 1);
    expect(calls.first.arguments, {'id': 1, 'text': 'Synthetic alpha.'});
    expect(calls.last.method, 'poll');
    expect(calls.last.arguments, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(completions, 1);
  });

  speechTest('late poll cannot complete a replacement',
      (tester, tts, calls, respond) async {
    var completions = 0;
    tts.setCompletionHandler(() => completions++);
    final oldPoll = Completer<Object?>();
    respond((call) async => call.method == 'poll' ? await oldPoll.future : 1);
    await tts.speak('Synthetic alpha.');
    await tester.pump(const Duration(milliseconds: 10));
    await tts.stop();
    await tts.speak('Synthetic beta.');
    oldPoll.complete({'id': 1, 'state': 'completed'});
    await tester.pump();
    expect(completions, 0);
    respond((call) async =>
        call.method == 'poll' ? {'id': 2, 'state': 'completed'} : 1);
    await tester.pump(const Duration(milliseconds: 10));
    expect(completions, 1);
  });

  speechTest('stop before speak acknowledgement revokes the request',
      (tester, tts, calls, respond) async {
    final accepted = Completer<Object?>();
    respond((call) async => call.method == 'speak' ? await accepted.future : 1);
    final speech = tts.speak('Synthetic alpha.');
    await tester.pump();
    await tts.stop();
    accepted.complete(1);
    expect(await speech, 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls.where((call) => call.method == 'poll'), isEmpty);
  });

  speechTest('native background cancellation is terminal',
      (tester, tts, calls, respond) async {
    var cancelled = 0;
    tts.setCancelHandler(() => cancelled++);
    respond((call) async =>
        call.method == 'poll' ? {'id': 1, 'state': 'cancelled'} : 1);
    await tts.speak('Synthetic alpha.');
    await tester.pump(const Duration(milliseconds: 10));
    expect(cancelled, 1);
    final count = calls.length;
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, count);
  });

  speechTest('explicit stop emits one cancellation and clears polling',
      (tester, tts, calls, respond) async {
    var cancelled = 0;
    tts.setCancelHandler(() => cancelled++);
    await tts.speak('Synthetic alpha.');
    await tts.stop();
    await tts.stop();
    await tester.pump(const Duration(seconds: 1));
    expect(cancelled, 1);
    expect(calls.where((call) => call.method == 'poll'), isEmpty);
  });

  speechTest('a late stop acknowledgement cannot cancel a replacement',
      (tester, tts, calls, respond) async {
    final stopped = Completer<Object?>();
    var cancelled = 0;
    var completed = 0;
    tts.setCancelHandler(() => cancelled++);
    tts.setCompletionHandler(() => completed++);
    respond((call) async => switch (call.method) {
          'stop' => await stopped.future,
          'poll' => {'id': 2, 'state': 'completed'},
          _ => 1,
        });
    await tts.speak('Synthetic alpha.');
    final stopping = tts.stop();
    await tts.speak('Synthetic beta.');
    stopped.complete(1);
    await stopping;
    expect(cancelled, 0);
    await tester.pump(const Duration(milliseconds: 10));
    expect(completed, 1);
  });

  speechTest('a missing speak acknowledgement requests a bounded purge',
      (tester, tts, calls, respond) async {
    final stalled = Completer<Object?>();
    respond((call) async => call.method == 'speak' ? await stalled.future : 1);
    final speech = tts.speak('Synthetic alpha.');
    final failure = expectLater(speech, throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await failure;
    expect(calls.map((call) => call.method), ['speak', 'stop']);
    stalled.complete(1);
    await tester.pump();
    await expectLater(tts.speak('Synthetic beta.'), throwsStateError);
  });

  speechTest('a rejected stop prevents subsequent speech',
      (tester, tts, calls, respond) async {
    var errors = 0;
    tts.setErrorHandler((_) => errors++);
    respond((call) async => call.method == 'stop' ? 0 : 1);
    await tts.speak('Synthetic alpha.');
    expect(await tts.stop(), 0);
    expect(errors, 1);
    await expectLater(tts.speak('Synthetic beta.'), throwsStateError);
    expect(calls.where((call) => call.method == 'speak').length, 1);
  });

  speechTest('malformed or mismatched status fails closed and purges audio',
      (tester, tts, calls, respond) async {
    var errors = 0;
    tts.setErrorHandler((_) => errors++);
    respond((call) async =>
        call.method == 'poll' ? {'id': 99, 'state': 'completed'} : 1);
    await tts.speak('Synthetic alpha.');
    await tester.pump(const Duration(milliseconds: 10));
    expect(errors, 1);
    expect(calls.last.method, 'stop');
    await expectLater(tts.speak('Synthetic beta.'), throwsStateError);
  });

  speechTest('a stalled poll is bounded and cannot emit a late completion',
      (tester, tts, calls, respond) async {
    var completions = 0;
    var errors = 0;
    final stalled = Completer<Object?>();
    tts.setCompletionHandler(() => completions++);
    tts.setErrorHandler((_) => errors++);
    respond((call) async => call.method == 'poll' ? await stalled.future : 1);
    await tts.speak('Synthetic alpha.');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(errors, 1);
    stalled.complete({'id': 1, 'state': 'completed'});
    await tester.pump();
    expect(completions, 0);
  });

  speechTest(
      'request bounds and concurrent speech reject before native dispatch',
      (tester, tts, calls, respond) async {
    for (final text in ['', 'synthetic\u0000text', '🧠' * 16385]) {
      await expectLater(tts.speak(text), throwsArgumentError);
    }
    expect(calls, isEmpty);
    await tts.speak('Synthetic alpha.');
    await expectLater(tts.speak('Synthetic beta.'), throwsStateError);
    expect(calls.where((call) => call.method == 'speak').length, 1);
  });

  speechTest('missing Windows owner never falls back to the plugin',
      (tester, tts, calls, respond) async {
    respond((call) async => throw MissingPluginException());
    await expectLater(
        tts.speak('Synthetic alpha.'), throwsA(isA<MissingPluginException>()));
    await expectLater(tts.speak('Synthetic beta.'), throwsStateError);
  });

  speechTest('voice settings use only the Windows local channel',
      (tester, tts, calls, respond) async {
    respond((call) async => call.method == 'getVoices' ? <Object?>[] : 1);
    expect(await tts.getVoices, isEmpty);
    await tts.setVoice({'name': 'Synthetic', 'locale': 'en-US'});
    await tts.setSpeechRate(0.5);
    await tts.setPitch(1.05);
    await tts.setVolume(1.0);
    await expectLater(tts.awaitSpeakCompletion(true), throwsUnsupportedError);
    expect(calls.map((call) => call.method),
        ['getVoices', 'setVoice', 'setSpeechRate', 'setPitch', 'setVolume']);
  });
}
