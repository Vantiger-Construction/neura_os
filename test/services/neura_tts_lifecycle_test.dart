import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/ambient_listening_service.dart';
import 'package:neuro_companion/services/neura_audio_focus.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';

/// No native speech, capture, network, files, preferences or real user text.
class _SyntheticTts extends FlutterTts {
  final spoken = <String>[];
  final calls = <String>[];
  Future<dynamic> Function()? onStop;
  Future<dynamic> Function(String)? onSpeak;
  Future<dynamic> Function()? onRate;
  Future<dynamic> Function()? onVoice;

  Future<void> event(String method, [dynamic arguments]) async {
    await platformCallHandler(MethodCall(method, arguments));
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) =>
      throw StateError('Native completion waiting must stay disabled.');

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('rate');
    return onRate == null ? 1 : await onRate!();
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    calls.add('pitch');
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    calls.add('volume');
    return 1;
  }

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async =>
      onVoice == null ? 1 : await onVoice!();
  @override
  Future<dynamic> get getVoices async => <dynamic>[];

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    calls.add('speak');
    return onSpeak == null ? 1 : await onSpeak!(text);
  }

  @override
  Future<dynamic> stop() async {
    calls.add('stop');
    return onStop == null ? 1 : await onStop!();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _SyntheticTts native;
  late NeuraTtsService service;
  late bool previousSafeMode;

  void lifecycleTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      previousSafeMode = SafeBoot.instance.safeMode.value;
      SafeBoot.instance.safeMode.value = false;
      native = _SyntheticTts();
      service = NeuraTtsService.forTesting(
        native,
        nativeCommandTimeout: const Duration(seconds: 1),
        speechTimeout: const Duration(seconds: 3),
      );
      try {
        await body(tester);
      } finally {
        native.onStop = null;
        final disposing = service.dispose().catchError((Object _) {});
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        await disposing;
        SafeBoot.instance.safeMode.value = previousSafeMode;
      }
    });
  }

  void expectIdle() {
    expect(NeuraAudioFocus.instance.speechActive, isFalse);
    expect(NeuraCompanionPresence.instance.state.value.voiceActive, isFalse);
  }

  test('proactive startup speech stays disabled pending Windows acceptance',
      () {
    expect(kEnableProactiveGreetingTts, isFalse);
  });

  lifecycleTest('empty and disabled speech do not initialize native TTS',
      (tester) async {
    await service.speak('  ');
    service.enabled = false;
    await service.speak('Synthetic disabled.');
    expect(native.calls, isEmpty);
    expectIdle();
  });

  lifecycleTest('warmup and speech share one initialization', (tester) async {
    final initializing = Completer<dynamic>();
    native.onRate = () => initializing.future;
    final first = service.warmUp();
    final second = service.warmUp();
    final speech = service.speak('Synthetic shared initialization.');
    await tester.pump();
    expect(native.calls, ['rate']);
    initializing.complete(1);
    await tester.pump();
    await first;
    await second;
    expect(native.calls.where((call) => call == 'rate').length, 1);
    expect(native.spoken, ['Synthetic shared initialization.']);
    await native.event('speak.onComplete');
    await speech;
    expectIdle();
  });

  lifecycleTest(
      'waits for callback and releases focus once on duplicate signals',
      (tester) async {
    var returned = false;
    final speech =
        service.speak('Synthetic alpha.').then((_) => returned = true);
    await tester.pump();
    expect(native.spoken, ['Synthetic alpha.']);
    expect(returned, isFalse);
    expect(NeuraAudioFocus.instance.speechActive, isTrue);
    await native.event('speak.onComplete');
    await native.event('speak.onComplete');
    await native.event('speak.onCancel');
    await speech;
    expectIdle();
  });

  lifecycleTest('stop during initialization invalidates the waiting request',
      (tester) async {
    final initializing = Completer<dynamic>();
    native.onRate = () => initializing.future;
    final speech = service.speak('Synthetic stale request.');
    await tester.pump();
    final stopping = service.stop();
    initializing.complete(1);
    await tester.pump();
    await stopping;
    expect(native.spoken, isEmpty);
    await speech;
    expectIdle();
  });

  lifecycleTest('Safe Mode entry and exit cannot revive a pending request',
      (tester) async {
    final initializing = Completer<dynamic>();
    native.onRate = () => initializing.future;
    final speech = service.speak('Synthetic stale request.');
    await tester.pump();
    SafeBoot.instance.safeMode.value = true;
    SafeBoot.instance.safeMode.value = false;
    initializing.complete(1);
    await tester.pump();
    expect(native.spoken, isEmpty);
    await speech;
    expectIdle();
  });

  lifecycleTest('concurrent requests serialize stop before the latest speak',
      (tester) async {
    await service.warmUp();
    final stopping = Completer<dynamic>();
    native.onStop = () => stopping.future;
    final first = service.speak('Synthetic alpha.');
    await tester.pump();
    final second = service.speak('Synthetic beta.');
    await tester.pump();
    native.onStop = null;
    stopping.complete(1);
    await tester.pump();
    expect(native.spoken, ['Synthetic beta.']);
    await native.event('speak.onComplete');
    await first;
    await second;
    expectIdle();
  });

  lifecycleTest('missing completion stops speech and reports a bounded failure',
      (tester) async {
    final speech = service.speak('Synthetic deadline.');
    final failure = expectLater(speech, throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await failure;
    expect(native.calls.where((c) => c == 'stop').length, 2);
    expectIdle();
    await expectLater(service.speak('Synthetic retry.'), throwsStateError);
  });

  lifecycleTest('rejection and a thrown speak release leases', (tester) async {
    native.onSpeak = (_) async => 0;
    await service.speak('Synthetic rejected.');
    expectIdle();
    native.onSpeak = (_) async => throw StateError('Synthetic failure');
    await expectLater(service.speak('Synthetic failed.'), throwsStateError);
    expectIdle();
  });

  lifecycleTest('callback error is a failure and cancel is terminal',
      (tester) async {
    final first = service.speak('Synthetic error callback.');
    final failure = expectLater(first, throwsStateError);
    await tester.pump();
    await native.event('speak.onError', 'Synthetic error');
    await failure;
    expectIdle();
    final second = service.speak('Synthetic cancelled callback.');
    await tester.pump();
    await native.event('speak.onCancel');
    await second;
    expectIdle();
  });

  lifecycleTest('completion before speak acknowledgement is retained',
      (tester) async {
    native.onSpeak = (_) async {
      await native.event('speak.onComplete');
      return 1;
    };
    await service.speak('Synthetic immediate completion.');
    expectIdle();
  });

  lifecycleTest(
      'late rejected acknowledgement cannot finish replacement speech',
      (tester) async {
    final acknowledgement = Completer<dynamic>();
    native.onSpeak = (_) => acknowledgement.future;
    final first = service.speak('Synthetic alpha.');
    await tester.pump();
    var returned = false;
    final second =
        service.speak('Synthetic beta.').then((_) => returned = true);
    await tester.pump();
    expect(native.spoken, ['Synthetic alpha.']);
    native.onSpeak = null;
    acknowledgement.complete(0);
    await tester.pump();
    await first;
    expect(native.spoken, ['Synthetic alpha.', 'Synthetic beta.']);
    expect(returned, isFalse);
    expect(NeuraAudioFocus.instance.speechActive, isTrue);
    await native.event('speak.onComplete');
    await second;
    expectIdle();
  });

  lifecycleTest('stop ignores callbacks until native stop acknowledges',
      (tester) async {
    var returned = false;
    final speech =
        service.speak('Synthetic alpha.').then((_) => returned = true);
    await tester.pump();
    final acknowledgement = Completer<dynamic>();
    native.onStop = () => acknowledgement.future;
    final stopping = service.stop();
    await tester.pump();
    await native.event('speak.onCancel');
    await native.event('speak.onComplete');
    expect(returned, isFalse);
    acknowledgement.complete(1);
    await stopping;
    await speech;
    expectIdle();
  });

  lifecycleTest('hung speak acknowledgement fails closed despite late response',
      (tester) async {
    final acknowledgement = Completer<dynamic>();
    native.onSpeak = (_) => acknowledgement.future;
    final failure = expectLater(
        service.speak('Synthetic hung.'), throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await failure;
    expectIdle();
    acknowledgement.complete(1);
    await tester.pump();
    await expectLater(service.speak('Synthetic retry.'), throwsStateError);
    expect(native.spoken, ['Synthetic hung.']);
  });

  lifecycleTest('hung initialization cannot resume configuring or speaking',
      (tester) async {
    final initializing = Completer<dynamic>();
    native.onRate = () => initializing.future;
    final failure = expectLater(service.speak('Synthetic hung init.'),
        throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await failure;
    initializing.complete(1);
    await tester.pump();
    expect(native.calls, ['rate']);
    expect(native.spoken, isEmpty);
    expectIdle();
  });

  lifecycleTest('stop failure releases leases and prevents further speech',
      (tester) async {
    final speech = service.speak('Synthetic alpha.');
    final failure = expectLater(speech, throwsStateError);
    await tester.pump();
    native.onStop = () async => throw StateError('Synthetic stop failure');
    await expectLater(service.stop(), throwsStateError);
    await failure;
    await expectLater(service.speak('Synthetic retry.'), throwsStateError);
    expectIdle();
  });

  lifecycleTest('hung stop releases leases with failure and blocks reuse',
      (tester) async {
    final speechFailure = expectLater(
        service.speak('Synthetic alpha.'), throwsA(isA<TimeoutException>()));
    await tester.pump();
    final acknowledgement = Completer<dynamic>();
    native.onStop = () => acknowledgement.future;
    final stopFailure =
        expectLater(service.stop(), throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await speechFailure;
    await stopFailure;
    expectIdle();
    acknowledgement.complete(1);
    await tester.pump();
    await expectLater(service.speak('Synthetic retry.'), throwsStateError);
    expect(native.spoken, ['Synthetic alpha.']);
  });

  lifecycleTest('rejected stop blocks a replacement utterance', (tester) async {
    final speechFailure =
        expectLater(service.speak('Synthetic alpha.'), throwsStateError);
    await tester.pump();
    native.onStop = () async => 0;
    await expectLater(service.speak('Synthetic beta.'), throwsStateError);
    await speechFailure;
    expect(native.spoken, ['Synthetic alpha.']);
    expectIdle();
  });

  lifecycleTest('Safe Mode blocks initialization and stops active playback',
      (tester) async {
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    native.calls.clear();
    await service.warmUp();
    await service.speak('Synthetic forbidden.');
    expect(await service.availableVoices(), isEmpty);
    expect(native.calls, isEmpty);
    SafeBoot.instance.safeMode.value = false;
    final speech = service.speak('Synthetic alpha.');
    await tester.pump();
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    await speech;
    expectIdle();
    expect(NeuraCompanionPresence.instance.state.value.isSafeMode, isTrue);
    SafeBoot.instance.safeMode.value = false;
    await tester.pump();
    expect(native.spoken, ['Synthetic alpha.']);
  });

  lifecycleTest('disposal revokes pending initialization and detaches listener',
      (tester) async {
    final initializing = Completer<dynamic>();
    native.onRate = () => initializing.future;
    final speech = service.speak('Synthetic disposed.');
    await tester.pump();
    final disposing = service.dispose();
    initializing.complete(1);
    await tester.pump();
    await disposing;
    await speech;
    final calls = native.calls.length;
    await service.dispose();
    SafeBoot.instance.safeMode.value = true;
    SafeBoot.instance.safeMode.value = false;
    await service.speak('Synthetic after disposal.');
    await tester.pump();
    expect(native.calls.length, calls);
    expect(native.spoken, isEmpty);
    expectIdle();
  });

  lifecycleTest('stop while preview selects a voice invalidates the preview',
      (tester) async {
    final selecting = Completer<dynamic>();
    native.onVoice = () => selecting.future;
    final preview = service.previewVoice(
        const NeuraVoiceOption(
            name: 'Synthetic', locale: 'en-US', gender: 'female'),
        'Synthetic sample.');
    await tester.pump();
    await service.stop();
    selecting.complete(1);
    await tester.pump();
    await preview;
    expect(native.spoken, isEmpty);
    expectIdle();
  });

  lifecycleTest('reentrant stop on focus acquisition prevents native speak',
      (tester) async {
    final subscription =
        NeuraAudioFocus.instance.speechActivity.listen((active) {
      if (active) unawaited(service.stop());
    });
    await tester.pump();
    final speech = service.speak('Synthetic revoked focus.');
    await tester.pump();
    expect(native.spoken, isEmpty);
    await speech;
    unawaited(subscription.cancel());
    expect(native.spoken, isEmpty);
    expectIdle();
  });

  group('process-scoped native queue', () {
    late _SyntheticTts sharedNative;
    late NeuraTtsService sharedService;

    setUpAll(() {
      // Like the application singleton, this service predates each widget
      // test's fake clock. Its idle queue must not retain that creation zone.
      sharedNative = _SyntheticTts();
      sharedService = NeuraTtsService.forTesting(sharedNative);
    });

    tearDownAll(() async {
      await sharedService.dispose();
    });

    for (final name in [
      'first stop completes inside the calling widget clock',
      'drained queue accepts a stop from the next widget clock',
    ]) {
      testWidgets(name, (tester) async {
        sharedNative.calls.clear();
        var stopped = false;
        final stopping = sharedService.stop().then((_) => stopped = true);
        await tester.pump();
        expect(stopped, isTrue);
        expect(sharedNative.calls, ['stop']);
        expect(sharedNative.spoken, isEmpty);
        await stopping;
        expectIdle();
      });
    }
  });
}
