import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/neura_voice_settings_screen.dart';
import 'package:neuro_companion/services/neura_startup_voice_prefs.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const tts = MethodChannel('flutter_tts');
  const input = MethodChannel('neura/local_speech_input');
  const permission = MethodChannel('flutter.baseflow.com/permissions/methods');
  bool granted = true;
  bool available = true;
  bool networkVoice = false;
  final spoken = <MethodCall>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    granted = true;
    available = true;
    networkVoice = false;
    spoken.clear();
    await NeuraPrefsCache.prefs.clear();
    NeuraStartupVoicePrefs.instance.enabled.value = false;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(tts, (call) async {
      if (call.method == 'getVoices') {
        return [
          {
            'name': 'Synthetic',
            'locale': 'en-US',
            'gender': 'female',
            'network_required': networkVoice ? '1' : '0'
          }
        ];
      }
      if (call.method == 'speak') spoken.add(call);
      return 1;
    });
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(input, (call) async => available);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        permission, (call) async => {7: granted ? 1 : 0});
  });
  tearDown(() {
    for (final channel in [tts, input, permission]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
  });

  void settingsTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      final platform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      try {
        await tester
            .pumpWidget(const MaterialApp(home: NeuraVoiceSettingsScreen()));
        await tester.pumpAndSettle();
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = platform;
      }
    });
  }

  settingsTest(
      'saved startup opt-in also enables reply speech and can be switched off',
      (tester) async {
    await NeuraTtsService.instance.setReplySpeechMode(NeuraReplySpeechMode.off);
    await tester.tap(find.byKey(const Key('startup-voice-switch')));
    await tester.pumpAndSettle();
    expect(NeuraStartupVoicePrefs.instance.enabled.value, isTrue);
    expect(NeuraPrefsCache.prefs.getBool(NeuraStartupVoicePrefs.key), isTrue);
    expect(NeuraTtsService.instance.replySpeechMode,
        NeuraReplySpeechMode.afterComplete);
    expect(find.text('Start voice now'), findsOneWidget);
    expect(NeuraPrefsCache.prefs.getBool('neura.wake_word.enabled.v1'), isNull);
    expect(NeuraPrefsCache.prefs.getBool('neura.ambient.listening.enabled.v1'),
        isNull);
    expect(spoken, isEmpty,
        reason: 'Changing a setting must not capture or speak yet.');
    await tester.tap(find.byKey(const Key('startup-voice-switch')));
    await tester.pumpAndSettle();
    expect(NeuraPrefsCache.prefs.getBool(NeuraStartupVoicePrefs.key), isFalse);
    expect(tester.takeException(), isNull);
  });

  settingsTest('denied microphone permission cannot save an opt-in',
      (tester) async {
    granted = false;
    await tester.tap(find.byKey(const Key('startup-voice-switch')));
    await tester.pumpAndSettle();
    expect(NeuraStartupVoicePrefs.instance.enabled.value, isFalse);
    expect(NeuraPrefsCache.prefs.getBool(NeuraStartupVoicePrefs.key), isNull);
    expect(find.text('Allow microphone access to use startup voice.'),
        findsOneWidget);
    expect(spoken, isEmpty);
  });

  settingsTest('network-only output voice cannot enable automatic speech',
      (tester) async {
    networkVoice = true;
    await tester.tap(find.byKey(const Key('startup-voice-switch')));
    await tester.pumpAndSettle();
    expect(NeuraStartupVoicePrefs.instance.enabled.value, isFalse);
    expect(find.text('No installed on-device voice.'), findsOneWidget);
    expect(spoken, isEmpty);
  });
}
