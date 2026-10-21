import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'neura.tts.voice_name': 'Old WinRT voice',
      'neura.tts.voice_locale': 'en-US',
    });
    await NeuraPrefsCache.init();
  });

  testWidgets('Windows service uses local owned speech with no plugin fallback',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final safeMode = SafeBoot.instance.safeMode.value;
    SafeBoot.instance.safeMode.value = true;
    const local = MethodChannel('neura/speech_synthesis');
    const legacy = MethodChannel('flutter_tts');
    final calls = <String>[];
    final selections = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(local,
        (call) async {
      calls.add(call.method);
      if (call.method == 'setVoice') {
        selections.add(call.arguments['name']);
        return call.arguments['name'] == 'Synthetic' ? 1 : 0;
      }
      return switch (call.method) {
        'getVoices' => [
            {'name': 'Synthetic', 'locale': 'en-US', 'gender': 'female'}
          ],
        'poll' => {'id': 1, 'state': 'completed'},
        _ => 1,
      };
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(legacy,
        (call) async {
      fail('The Windows service must not invoke the old speech plugin.');
    });
    final service = NeuraTtsService.instance;
    try {
      await service.warmUp();
      await service.speak('Synthetic blocked.');
      expect(calls, isEmpty);
      SafeBoot.instance.safeMode.value = false;
      final speech = service.speak('Synthetic Windows routing.');
      await tester.pump();
      expect(calls, contains('speak'));
      await tester.pump(const Duration(milliseconds: 40));
      await speech;
      expect(calls, contains('poll'));
      expect(selections, ['Old WinRT voice', 'Synthetic']);
      expect(service.selectedVoiceName, 'Synthetic');
      const unavailable = NeuraVoiceOption(
          name: 'Unavailable voice', locale: 'en-US', gender: 'female');
      await service.setVoice(unavailable);
      await service.previewVoice(unavailable, 'Synthetic rejected preview.');
      expect(service.selectedVoiceName, 'Synthetic');
      expect(NeuraPrefsCache.prefs.getString('neura.tts.voice_name'),
          'Old WinRT voice');
      expect(calls.where((method) => method == 'speak').length, 1);
    } finally {
      await service.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(local, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(legacy, null);
      SafeBoot.instance.safeMode.value = safeMode;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
