import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
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
}
