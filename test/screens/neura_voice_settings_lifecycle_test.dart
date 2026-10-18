import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/neura_voice_settings_screen.dart';
import 'package:neuro_companion/services/neura_audio_focus.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';

void main() {
  testWidgets('leaving voice settings stops its synthetic preview',
      (tester) async {
    final previousSafeMode = SafeBoot.instance.safeMode.value;
    SafeBoot.instance.safeMode.value = false;
    const channel = MethodChannel('flutter_tts');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      if (call.method == 'getVoices') {
        return [
          {'name': 'Synthetic', 'locale': 'en-US', 'gender': 'female'},
        ];
      }
      if (call.method == 'awaitSpeakCompletion') {
        fail('Native completion waiting must remain disabled.');
      }
      return 1;
    });
    try {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const NeuraVoiceSettingsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play a sample'));
      await tester.pumpAndSettle();
      expect(calls.where((method) => method == 'speak').length, 1);
      expect(NeuraAudioFocus.instance.speechActive, isTrue);
      calls.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(calls.first, 'stop');
      expect(calls, contains('setVoice'));
      expect(NeuraAudioFocus.instance.speechActive, isFalse);
    } finally {
      await NeuraTtsService.instance.stop();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      SafeBoot.instance.safeMode.value = previousSafeMode;
    }
  });
}
