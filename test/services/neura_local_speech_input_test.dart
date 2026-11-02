import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_local_speech_input.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/local_speech_input');
  late NeuraLocalSpeechInput input;
  late bool foreground;
  late bool granted;
  late List<MethodCall> calls;
  Future<Object?> Function(MethodCall)? handler;

  setUp(() {
    foreground = true;
    granted = true;
    calls = [];
    handler = null;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (handler != null) return handler!(call);
      return call.method == 'isAvailable' || call.method == 'start'
          ? true
          : null;
    });
  });

  tearDown(() async {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  void localTest(String name, Future<void> Function() body) {
    test(name, () async {
      input = NeuraLocalSpeechInput(
          foreground: () => foreground, requestPermission: () async => granted);
      try {
        await body();
      } finally {
        await input.dispose();
      }
    });
  }

  localTest('permission denial never starts the native microphone', () async {
    granted = false;
    expect(await input.startRecording(), isFalse);
    expect(calls.map((c) => c.method), ['isAvailable']);
    expect(input.isListening, isFalse);
  });

  localTest('unavailable local engine never falls back to OS dictation',
      () async {
    handler = (call) async => false;
    expect(await input.startRecording(), isFalse);
    expect(calls.map((c) => c.method), ['isAvailable']);
  });

  localTest('focus loss during availability check cancels before mic start',
      () async {
    final gate = Completer<bool>();
    handler = (call) async => gate.future;
    final starting = input.startRecording();
    await Future<void>.delayed(Duration.zero);
    foreground = false;
    gate.complete(true);
    expect(await starting, isFalse);
    expect(calls.map((c) => c.method), ['isAvailable']);
  });

  localTest('late native start after Safe Mode is stopped again', () async {
    final start = Completer<bool>();
    handler = (call) async => call.method == 'start' ? start.future : true;
    final starting = input.startRecording();
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), ['isAvailable', 'start']);
    SafeBoot.instance.safeMode.value = true;
    await Future<void>.delayed(Duration.zero);
    start.complete(true);
    expect(await starting, isFalse);
    expect(
        calls.where((c) => c.method == 'stop').length, greaterThanOrEqualTo(2));
    expect(input.isListening, isFalse);
  });

  localTest('stale poll after Stop cannot emit private speech', () async {
    final poll = Completer<Map<String, Object>>();
    handler = (call) async => call.method == 'poll' ? poll.future : true;
    final heard = <String>[];
    final sub = input.finalPhraseStream.listen(heard.add);
    expect(await input.startRecording(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final session = (calls.last.arguments as Map)['session'] as int;
    final stopping = input.stopRecording();
    await Future<void>.delayed(Duration.zero);
    poll.complete({
      'session': session,
      'listening': true,
      'text': 'Synthetic stale phrase',
      'final': true
    });
    await Future<void>.delayed(Duration.zero);
    await stopping;
    expect(heard, isEmpty);
    expect(input.isListening, isFalse);
    await sub.cancel();
  });

  localTest('only current local finals reach chat and Stop discards its buffer',
      () async {
    final heard = <String>[];
    final sub = input.finalPhraseStream.listen(heard.add);
    handler = (call) async {
      if (call.method != 'poll') return true;
      return {
        'session': (call.arguments as Map)['session'],
        'listening': true,
        'text': 'Synthetic local phrase',
        'final': true
      };
    };
    expect(await input.startRecording(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await Future<void>.delayed(Duration.zero);
    expect(heard, ['Synthetic local phrase']);
    expect(await input.stopRecording(), 'Synthetic local phrase');
    expect(await input.stopRecording(), isEmpty);
    await sub.cancel();
  });

  localTest('background polling stops capture and discards pending words',
      () async {
    expect(await input.startRecording(), isTrue);
    foreground = false;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(input.isListening, isFalse);
    expect(await input.stopRecording(), isEmpty);
    expect(calls.any((c) => c.method == 'poll'), isFalse);
    expect(calls.any((c) => c.method == 'stop'), isTrue);
  });

  localTest('unconfirmed native stop withholds text and blocks another capture',
      () async {
    handler = (call) async {
      if (call.method == 'stop') {
        throw PlatformException(code: 'synthetic-stop-failure');
      }
      if (call.method == 'poll') {
        return {
          'session': (call.arguments as Map)['session'],
          'listening': true,
          'text': 'Synthetic private phrase',
          'final': true,
        };
      }
      return true;
    };
    expect(await input.startRecording(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(await input.stopRecording(), isEmpty);
    expect(await input.startRecording(), isFalse);
    await expectLater(
        input.shutdownForDataWipe(), throwsA(isA<PlatformException>()));
  });
}
