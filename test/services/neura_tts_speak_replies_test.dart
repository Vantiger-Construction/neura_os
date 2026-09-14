import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  test('speak-replies-aloud defaults to off', () {
    expect(NeuraTtsService.instance.speakRepliesEnabled, isFalse);
  });

  test('setSpeakRepliesEnabled persists and is reflected immediately',
      () async {
    final service = NeuraTtsService.instance;
    await service.setSpeakRepliesEnabled(true);
    expect(service.speakRepliesEnabled, isTrue);

    await service.setSpeakRepliesEnabled(false);
    expect(service.speakRepliesEnabled, isFalse);
  });
}
