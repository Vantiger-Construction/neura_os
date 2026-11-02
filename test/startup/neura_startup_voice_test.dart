import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/modules/chat/neura_chat_screen.dart';
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_speech_input.dart';
import 'package:neuro_companion/services/neura_startup_voice_prefs.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

class _LocalInput implements NeuraSpeechInput {
  final transcripts = StreamController<String>.broadcast();
  final finals = StreamController<String>.broadcast();
  final statuses = StreamController<String>.broadcast();
  int starts = 0;
  @override
  bool isListening = false;
  @override
  Stream<String> get transcriptStream => transcripts.stream;
  @override
  Stream<String> get finalPhraseStream => finals.stream;
  @override
  Stream<String> get statusStream => statuses.stream;
  @override
  Future<bool> startRecording() async {
    starts++;
    isListening = true;
    return true;
  }

  @override
  Future<String> stopRecording() async {
    isListening = false;
    return '';
  }

  Future<void> close() async {
    await transcripts.close();
    await finals.close();
    await statuses.close();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();
  late _LocalInput input;
  late NeuraShellState shell;
  final spoken = <String>[];

  Future<void> completeGreeting() async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(channel.name,
        codec.encodeMethodCall(const MethodCall('speak.onComplete')), (_) {});
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    await NeuraPrefsCache.prefs.clear();
    spoken.clear();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraStartupVoicePrefs.instance.enabled.value = true;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'getVoices') {
        return [
          {
            'name': 'Synthetic offline',
            'locale': 'en-US',
            'network_required': '0'
          }
        ];
      }
      if (call.method == 'speak') {
        spoken.add(call.arguments is Map
            ? (call.arguments as Map)['text'] as String
            : call.arguments as String);
      }
      return 1;
    });
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    NeuraStartupVoicePrefs.instance.enabled.value = false;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  Future<void> pumpChat(WidgetTester tester, {bool startup = true}) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    input = _LocalInput();
    shell = NeuraShellState();
    await tester.pumpWidget(NeuraShellScope(
        notifier: shell,
        child: MaterialApp(
            home:
                NeuraChatScreen(startWithVoice: startup, speechInput: input))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {});
    await tester.pump();
  }

  void startupTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      final platform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        final stopping = NeuraTtsService.instance.stop();
        await tester.pump();
        await stopping;
        await input.close();
        shell.dispose();
        debugDefaultTargetPlatformOverride = platform;
      }
    });
  }

  startupTest(
      'saved opt-in greets once, then opens the microphone after completion',
      (tester) async {
    await pumpChat(tester);
    expect(spoken, hasLength(1));
    expect(input.starts, 0, reason: 'Neura must not transcribe her greeting.');
    await completeGreeting();
    await tester.pump();
    expect(input.starts, 1);
    expect(input.isListening, isTrue);
    await tester.pump();
    expect(spoken, hasLength(1));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(input.isListening, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(input.starts, 1,
        reason: 'Foreground return cannot restart capture silently.');
    await tester.pumpWidget(const SizedBox());
  });

  for (final reason in [
    'opt-out',
    'safe-mode',
    'restart-required',
    'background',
    'dispose',
    'stop'
  ]) {
    startupTest('$reason during the greeting prevents a late microphone start',
        (tester) async {
      await pumpChat(tester);
      expect(spoken, hasLength(1));
      switch (reason) {
        case 'opt-out':
          NeuraStartupVoicePrefs.instance.enabled.value = false;
        case 'safe-mode':
          SafeBoot.instance.safeMode.value = true;
        case 'restart-required':
          SafeBoot.instance.restartRequired.value = true;
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
        case 'stop':
          await tester.tap(find.byTooltip('Talk freely (hands-free)'));
      }
      await completeGreeting();
      await tester.pump();
      expect(input.starts, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }

  startupTest('ordinary chat stays silent even with startup opt-in',
      (tester) async {
    await pumpChat(tester, startup: false);
    expect(spoken, isEmpty);
    expect(input.starts, 0);
    await tester.pumpWidget(const SizedBox());
  });

  startupTest('startup route without a saved opt-in never activates audio',
      (tester) async {
    NeuraStartupVoicePrefs.instance.enabled.value = false;
    await pumpChat(tester);
    expect(spoken, isEmpty);
    expect(input.starts, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
