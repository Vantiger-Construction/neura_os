import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_startup_voice_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

import '../helpers/data_wipe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing opt-in stays off; explicit choice survives reload', () async {
    await DataWipeFixture.create();
    final prefs = NeuraStartupVoicePrefs.forTesting();
    await prefs.init();
    expect(prefs.enabled.value, isFalse);
    await prefs.setEnabled(true);
    final restored = NeuraStartupVoicePrefs.forTesting();
    await restored.init();
    expect(restored.enabled.value, isTrue);
    await restored.setEnabled(false);
    await prefs.init();
    expect(prefs.enabled.value, isFalse);
  });

  test('wipe drains submitted startup opt-in before preferences are removed',
      () async {
    final fixture = await DataWipeFixture.create();
    final prefs = NeuraStartupVoicePrefs.forTesting();
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.preferences.beforeSet = (key) async {
      if (!key.contains(NeuraStartupVoicePrefs.key)) return;
      entered.complete();
      await release.future;
    };
    final writing = prefs.setEnabled(true);
    await entered.future;
    prefs.resetAfterDataWipe();
    var drained = false;
    final draining = prefs.drainForDataWipe().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    expect(prefs.enabled.value, isFalse);
    release.complete();
    await writing;
    await draining;
    expect(prefs.enabled.value, isFalse,
        reason: 'Late writes cannot restore live consent.');
    await NeuraPrefsCache.prefs.clear();
    await NeuraPrefsCache.prefs.reload();
    expect(NeuraPrefsCache.prefs.getBool(NeuraStartupVoicePrefs.key), isNull);
    await expectLater(prefs.setEnabled(true), throwsStateError);
  });
}
