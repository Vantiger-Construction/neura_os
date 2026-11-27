import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_language.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';

/// Synthetic voices only: no native speech, network or preferences.
class _VoicesTts extends FlutterTts {
  final spoken = <String>[];
  final voices = <Map<String, String>>[];

  Future<void> event(String method, [dynamic arguments]) async {
    await platformCallHandler(MethodCall(method, arguments));
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) =>
      throw StateError('Native completion waiting must stay disabled.');
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    voices.add(voice);
    return 1;
  }

  @override
  Future<dynamic> get getVoices async => <dynamic>[
        {'name': 'Synthetic Aria', 'locale': 'en-US', 'gender': 'female'},
        {'name': 'Synthetic Pablo', 'locale': 'es-ES', 'gender': 'male'},
        {'name': 'Synthetic Helena', 'locale': 'es-ES', 'gender': 'female'},
        {
          'name': 'Synthetic Online Elsa',
          'locale': 'it-IT',
          'gender': 'female',
          'network_required': '1',
        },
        {'name': 'Synthetic Hedda', 'locale': 'de_DE', 'gender': 'female'},
      ];

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _VoicesTts native;
  late NeuraTtsService service;

  void voiceTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      SafeBoot.instance.safeMode.value = false;
      native = _VoicesTts();
      service = NeuraTtsService.forTesting(
        native,
        nativeCommandTimeout: const Duration(seconds: 1),
        speechTimeout: const Duration(seconds: 3),
      );
      try {
        await body(tester);
      } finally {
        final disposing = service.dispose().catchError((Object _) {});
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        await disposing;
      }
    });
  }

  Future<void> say(WidgetTester tester, String text) async {
    final speaking = service.speak(text);
    await tester.pump();
    await tester.pump();
    if (native.spoken.isNotEmpty && native.spoken.last == text) {
      await native.event('speak.onComplete');
    }
    await tester.pump();
    await speaking;
  }

  voiceTest('a Spanish reply uses a Spanish voice, then returns', (
    tester,
  ) async {
    await service.warmUp();
    native.voices.clear();

    service.setReplyLanguage(NeuraLanguage.es);
    await say(tester, 'Hola, estoy aquí.');
    expect(native.spoken, ['Hola, estoy aquí.']);
    // The female voice is preferred, as for English.
    expect(native.voices.single['name'], 'Synthetic Helena');

    // The same language does not change the voice again.
    await say(tester, 'Sigo aquí.');
    expect(native.voices, hasLength(1));

    service.setReplyLanguage(null);
    await say(tester, 'Back in English.');
    expect(native.voices.last['locale'], 'en-US');
  });

  voiceTest('a language without a local voice is shown, never misread', (
    tester,
  ) async {
    await service.warmUp();
    service.setReplyLanguage(NeuraLanguage.it);
    await say(tester, 'Ciao, sono qui.');
    // The only Italian voice needs the network; nothing is spoken.
    expect(native.spoken, isEmpty);
    expect(service.missingVoice.value, NeuraLanguage.it);

    service.setReplyLanguage(NeuraLanguage.fr);
    await say(tester, 'Bonjour.');
    expect(native.spoken, isEmpty);
    expect(service.missingVoice.value, NeuraLanguage.fr);
  });

  voiceTest('regional tags with either separator count', (tester) async {
    final german = await service.voicesFor(NeuraLanguage.de);
    expect(german.map((v) => v.name), ['Synthetic Hedda']);
    final spanish = await service.voicesFor(NeuraLanguage.es);
    expect(spanish, hasLength(2));
    expect(await service.voicesFor(NeuraLanguage.fr), isEmpty);
  });

  voiceTest('English replies never query voices again', (tester) async {
    await service.warmUp();
    native.voices.clear();
    service.setReplyLanguage(NeuraLanguage.en);
    await say(tester, 'Hello.');
    expect(native.spoken, ['Hello.']);
    expect(native.voices, isEmpty);
  });
}
