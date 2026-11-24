import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_startup_voice_prefs.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  test('automatic reply speech defaults to off', () {
    final service = NeuraTtsService.instance;
    expect(service.replySpeechMode, NeuraReplySpeechMode.off);
    expect(service.speakRepliesEnabled, isFalse);
  });

  test('each explicit reply speech mode persists', () async {
    final service = NeuraTtsService.instance;

    await service.setReplySpeechMode(NeuraReplySpeechMode.afterComplete);
    expect(service.replySpeechMode, NeuraReplySpeechMode.afterComplete);
    expect(service.speakRepliesEnabled, isTrue);

    await service.setReplySpeechMode(NeuraReplySpeechMode.streamed);
    expect(service.replySpeechMode, NeuraReplySpeechMode.streamed);
    expect(service.speakRepliesEnabled, isTrue);

    await service.setReplySpeechMode(NeuraReplySpeechMode.off);
    expect(service.replySpeechMode, NeuraReplySpeechMode.off);
    expect(service.speakRepliesEnabled, isFalse);
  });

  test('legacy boolean setter maps to streamed or off', () async {
    final service = NeuraTtsService.instance;

    await service.setSpeakRepliesEnabled(true);
    expect(service.replySpeechMode, NeuraReplySpeechMode.streamed);

    await service.setSpeakRepliesEnabled(false);
    expect(service.replySpeechMode, NeuraReplySpeechMode.off);
  });

  group('reply sound at startup', () {
    final nativeCalls = <String>[];
    const channels = [
      MethodChannel('flutter_tts'),
      MethodChannel('neura/speech_synthesis'),
      MethodChannel('neura/local_speech_input'),
      MethodChannel('flutter.baseflow.com/permissions/methods'),
    ];

    setUp(() async {
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
      await NeuraPrefsCache.prefs.clear();
      await NeuraTtsService.instance.setReplySpeechMode(NeuraReplySpeechMode.off);
      await NeuraPrefsCache.prefs.setDouble('neura.tts.volume', 0.0);
      await NeuraPrefsCache.prefs.setBool(NeuraStartupVoicePrefs.key, false);
      await NeuraPrefsCache.prefs.setString('synthetic.unrelated', 'keep');
      nativeCalls.clear();
      for (final channel in channels) {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          nativeCalls.add('${channel.name}/${call.method}');
          return 1;
        });
      }
    });

    tearDown(() {
      for (final channel in channels) {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      }
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
    });

    test('normal launch restores audible replies without starting native voice',
        () async {
      final service = NeuraTtsService.instance;
      expect(service.replySoundOnStartup, isTrue);
      await service.prepareReplySoundForStartup();

      expect(service.replySpeechMode, NeuraReplySpeechMode.afterComplete);
      expect(NeuraPrefsCache.prefs.getDouble('neura.tts.volume'), 0.7);
      expect(service.volume, 0.7);
      expect(NeuraPrefsCache.prefs.getBool(NeuraStartupVoicePrefs.key), isFalse);
      expect(NeuraPrefsCache.prefs.getString('synthetic.unrelated'), 'keep');
      expect(nativeCalls, isEmpty);
    });

    test('streamed replies and an existing audible volume are preserved',
        () async {
      final service = NeuraTtsService.instance;
      await service.setReplySpeechMode(NeuraReplySpeechMode.streamed);
      await NeuraPrefsCache.prefs.setDouble('neura.tts.volume', 0.35);
      await service.prepareReplySoundForStartup();

      expect(service.replySpeechMode, NeuraReplySpeechMode.streamed);
      expect(service.volume, 0.35);
      expect(NeuraPrefsCache.prefs.getDouble('neura.tts.volume'), 0.35);
      expect(nativeCalls, isEmpty);
    });

    for (final boundary in ['opt-out', 'Safe Mode', 'restart']) {
      test('$boundary keeps muted preferences and native voice untouched',
          () async {
        final service = NeuraTtsService.instance;
        if (boundary == 'opt-out') {
          await service.setReplySoundOnStartup(false);
        } else if (boundary == 'Safe Mode') {
          SafeBoot.instance.safeMode.value = true;
        } else {
          SafeBoot.instance.restartRequired.value = true;
        }
        await service.prepareReplySoundForStartup();

        expect(service.replySpeechMode, NeuraReplySpeechMode.off);
        expect(NeuraPrefsCache.prefs.getDouble('neura.tts.volume'), 0.0);
        expect(NeuraPrefsCache.prefs.getBool(NeuraStartupVoicePrefs.key), isFalse);
        expect(nativeCalls, isEmpty);
      });
    }
  });
}
