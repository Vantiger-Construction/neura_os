import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_speech_to_text_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/speech_recognition');
  const codec = StandardMethodCodec();

  Future<void> native(String method, [Object? arguments]) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'isAvailable') return true;
      if (call.method == 'stop') await native('onStopped');
      return true;
    });
  });

  tearDown(() async {
    await NeuraSpeechToTextService.instance.stopRecording();
    SafeBoot.instance.safeMode.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('WinRT bridge exposes confidence separately from transcript', () async {
    final service = NeuraSpeechToTextService.instance;
    final segmentFuture = service.segmentStream.firstWhere(
      (segment) => segment.isFinal,
    );

    expect(await service.isAvailable(), isTrue);
    expect(await service.startRecording(), isTrue);
    await native('onListening');
    await native('onFinal', {
      'text': 'private spoken phrase',
      'confidence': 0.65,
    });

    final segment = await segmentFuture.timeout(const Duration(seconds: 1));
    expect(segment.text, 'private spoken phrase');
    expect(segment.confidence, 0.65);
    expect(segment.engineId, 'windows_winrt');
  });

  test('late native metadata is discarded after Safe Mode', () async {
    final service = NeuraSpeechToTextService.instance;
    final received = <Object>[];
    final subscription = service.segmentStream.listen(received.add);
    expect(await service.startRecording(), isTrue);
    await native('onListening');

    SafeBoot.instance.safeMode.value = true;
    await native('onFinal', {'text': 'must be ignored', 'confidence': 0.9});
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await subscription.cancel();
  });
}
