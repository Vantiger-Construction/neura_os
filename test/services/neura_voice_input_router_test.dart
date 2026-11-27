import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_local_speech_input.dart';
import 'package:neuro_companion/services/neura_on_device_speech_input.dart';
import 'package:neuro_companion/services/neura_speech_engine.dart';
import 'package:neuro_companion/services/neura_voice_input_router.dart';

/// Synthetic stand-in for the Sherpa-ONNX native engine.
final class _FakeEngine implements NeuraSpeechEngine {
  bool available = true;
  bool startResult = true;
  String stopText = '';
  int starts = 0;
  int stops = 0;
  bool _listening = false;
  final _segments = StreamController<NeuraSpeechSegment>.broadcast();

  void emit(String text, {bool isFinal = false}) {
    _segments.add(
      NeuraSpeechSegment(
        engineId: id,
        text: text,
        isFinal: isFinal,
        observedAtUtc: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  String get id => 'fake_on_device';

  @override
  NeuraSpeechEngineCapabilities get capabilities =>
      const NeuraSpeechEngineCapabilities(
        onDevice: true,
        supportsPartialResults: true,
        supportsConfidence: false,
        supportedPlatforms: {'windows'},
        experimental: true,
      );

  @override
  Stream<NeuraSpeechSegment> get segments => _segments.stream;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> start() async {
    starts++;
    _listening = startResult;
    return startResult;
  }

  @override
  Future<String> stop() async {
    stops++;
    _listening = false;
    return stopText;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const sapi = MethodChannel('neura/local_speech_input');
  late List<String> sapiCalls;
  late bool foreground;
  late _FakeEngine engine;
  late NeuraOnDeviceSpeechInput onDevice;
  late NeuraLocalSpeechInput local;
  late NeuraVoiceInputRouter router;

  setUp(() {
    sapiCalls = [];
    foreground = true;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(sapi,
        (call) async {
      sapiCalls.add(call.method);
      if (call.method == 'poll') {
        final args = call.arguments as Map;
        return {'session': args['session'], 'text': '', 'listening': true};
      }
      return call.method == 'isAvailable' || call.method == 'start'
          ? true
          : null;
    });
    engine = _FakeEngine();
    onDevice = NeuraOnDeviceSpeechInput(
      engine: engine,
      foreground: () => foreground,
      silenceWindow: const Duration(milliseconds: 50),
    );
    local = NeuraLocalSpeechInput(
      foreground: () => foreground,
      requestPermission: () async => true,
    );
    router = NeuraVoiceInputRouter(
      local: local,
      onDevice: () => onDevice,
      optedIn: () => true,
    );
  });

  tearDown(() async {
    await router.dispose();
    await local.dispose();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(sapi, null);
  });

  test('uses the offline streaming engine whenever it reports available',
      () async {
    final finals = <String>[];
    final partials = <String>[];
    final subs = [
      router.finalPhraseStream.listen(finals.add),
      router.transcriptStream.listen(partials.add),
    ];

    expect(await router.startRecording(), isTrue);
    expect(router.activeEngine, 'sherpa');
    expect(sapiCalls, isNot(contains('start')));

    engine.emit('IS CAMERA');
    engine.emit('IS CAMERA HAWK ON', isFinal: true);
    await Future<void>.delayed(Duration.zero);
    expect(partials.first, 'Is camera');
    expect(finals, ['Is camera hawk on']);

    engine.stopText = 'IS CAMERA HAWK ON';
    expect(await router.stopRecording(), 'Is camera hawk on');
    expect(engine.stops, 1);
    for (final sub in subs) {
      await sub.cancel();
    }
  });

  test('keeps the existing local recognizer when the engine is unavailable',
      () async {
    engine.available = false;
    expect(await router.startRecording(), isTrue);
    expect(router.activeEngine, 'sapi');
    expect(engine.starts, 0);
    expect(sapiCalls, contains('start'));
    await router.stopRecording();
  });

  test('falls back to the local recognizer when the engine refuses start',
      () async {
    engine.startResult = false;
    expect(await router.startRecording(), isTrue);
    expect(router.activeEngine, 'sapi');
    await router.stopRecording();
  });

  test('never starts offline capture in Safe Mode or in the background',
      () async {
    SafeBoot.instance.safeMode.value = true;
    expect(await onDevice.startRecording(), isFalse);
    expect(onDevice.lastFailure, 'safe_mode');
    SafeBoot.instance.safeMode.value = false;

    foreground = false;
    expect(await onDevice.startRecording(), isFalse);
    expect(onDevice.lastFailure, 'background');
    expect(engine.starts, 0);
  });

  test('Safe Mode stops an active offline session and drops its text',
      () async {
    expect(await onDevice.startRecording(), isTrue);
    engine.emit('PRIVATE WORDS');
    engine.stopText = 'PRIVATE WORDS';
    SafeBoot.instance.safeMode.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(onDevice.isListening, isFalse);
    expect(engine.stops, 1);
    expect(await onDevice.stopRecording(), '');
  });

  test('ends a silent turn and reports it just like the local recognizer',
      () async {
    final statuses = <String>[];
    final sub = onDevice.statusStream.listen(statuses.add);
    expect(await onDevice.startRecording(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(onDevice.isListening, isFalse);
    expect(statuses, [NeuraLocalSpeechInput.silenceEnded]);
    await sub.cancel();
  });

  test('without the runtime opt-in the streaming engine is never queried',
      () async {
    final plain = NeuraVoiceInputRouter(
      local: local,
      onDevice: () => onDevice,
      optedIn: () => false,
    );
    expect(await plain.startRecording(), isTrue);
    expect(plain.activeEngine, 'sapi');
    expect(engine.starts, 0);
    await plain.stopRecording();
    await plain.dispose();
  });

  test('data-wipe shutdown stops the offline engine', () async {
    expect(await router.startRecording(), isTrue);
    await router.shutdownOnDeviceForDataWipe();
    expect(engine.stops, 1);
    expect(onDevice.isListening, isFalse);
  });
}
