import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/emotion_analysis_service.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/services/neura_voice_tone.dart';

/// Records engine settings; no native speech or real user text.
class _RecordingTts extends FlutterTts {
  final calls = <String>[];

  Future<void> event(String method) =>
      platformCallHandler(MethodCall(method, null));

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('rate ${rate.toStringAsFixed(3)}');
    return 1;
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    calls.add('pitch ${pitch.toStringAsFixed(3)}');
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> setVoice(Map<String, String> voice) async => 1;
  @override
  Future<dynamic> get getVoices async => <dynamic>[];
  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    calls.add('speak');
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;
}

void main() {
  const reader = EmotionAnalysisService();

  test('hard feelings slow and soften her voice; good news brightens it', () {
    final sad = NeuraVoiceTone.forFeeling(
      reader.read('I feel so alone and sad tonight'),
    );
    expect(sad.rate, lessThan(1));
    expect(sad.pitch, lessThan(1));

    final anxious = NeuraVoiceTone.forFeeling(
      reader.read("I'm really anxious about tomorrow"),
    );
    expect(anxious.rate, lessThan(1));

    final happy = NeuraVoiceTone.forFeeling(
      reader.read('I got the job!! I am so happy'),
    );
    expect(happy.rate, greaterThan(1));
    expect(happy.pitch, greaterThan(1));

    expect(
      NeuraVoiceTone.forFeeling(reader.read('What time is it?')),
      NeuraVoiceTone.neutral,
    );
  });

  test('crisis language always gets the steady voice, never a bright one', () {
    expect(
      NeuraVoiceTone.forFeeling(reader.read('I am so happy'), crisis: true),
      NeuraVoiceTone.steady,
    );
  });

  test('every lean stays subtle', () {
    for (final read in [
      const EmotionRead(primary: 'grief', intensity: 1),
      const EmotionRead(primary: 'joy', intensity: 1),
      const EmotionRead(primary: 'anger', intensity: 1),
      const EmotionRead(primary: 'joy', secondary: 'exhaustion'),
      const EmotionRead(masked: true),
    ]) {
      final tone = NeuraVoiceTone.forFeeling(read);
      expect(tone.rate, inInclusiveRange(0.88, 1.06), reason: '$read');
      expect(tone.pitch, inInclusiveRange(0.96, 1.05), reason: '$read');
    }
  });

  testWidgets('the tone is applied before speaking and only when it changes', (
    tester,
  ) async {
    final previousSafeMode = SafeBoot.instance.safeMode.value;
    SafeBoot.instance.safeMode.value = false;
    final native = _RecordingTts();
    final service = NeuraTtsService.forTesting(
      native,
      nativeCommandTimeout: const Duration(seconds: 1),
      speechTimeout: const Duration(seconds: 3),
    );
    Future<void> say(String text) async {
      final done = service.speak(text);
      await tester.pump();
      await native.event('speak.onComplete');
      await tester.pump();
      await done;
    }

    try {
      await say('Hello.');
      native.calls.clear();
      service.setReplyTone(NeuraVoiceTone.steady);
      await say('I am here.');
      await say('Take your time.');
      expect(native.calls, [
        'rate ${(0.5 * 0.88).toStringAsFixed(3)}',
        'pitch ${(1.05 * 0.96).toStringAsFixed(3)}',
        'speak',
        'speak',
      ]);
      native.calls.clear();
      service.setReplyTone(NeuraVoiceTone.neutral);
      await say('Okay.');
      expect(native.calls, ['rate 0.500', 'pitch 1.050', 'speak']);
    } finally {
      final disposing = service.dispose().catchError((Object _) {});
      await tester.pump(const Duration(seconds: 4));
      await disposing;
      SafeBoot.instance.safeMode.value = previousSafeMode;
    }
  });
}
