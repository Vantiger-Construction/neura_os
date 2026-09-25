import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/modules/chat/neura_chat_screen.dart';
import 'package:neuro_companion/modules/mood/mood_checkin_screen.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_speech_to_text_service.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/services/wake_word_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/speech_recognition');
  const codec = StandardMethodCodec();
  final calls = <String>[];
  Completer<void>? stopGate;
  late NeuraShellState shell;

  Future<void> native(String method, [String? text]) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, text)),
      (_) {},
    );
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    calls.clear();
    stopGate = null;
    SafeBoot.instance.safeMode.value = false;
    WakeWordPrefsController.instance.enabled.value = false;
    await NeuraPrefsCache.prefs.clear();
    await NeuraTtsService.instance.setReplySpeechMode(NeuraReplySpeechMode.off);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      if (call.method == 'stop') {
        final gate = stopGate;
        if (gate != null) await gate.future;
        await native('onStopped');
      }
      return null;
    });
  });

  tearDown(() async {
    if (stopGate != null && !stopGate!.isCompleted) stopGate!.complete();
    await NeuraSpeechToTextService.instance.stopRecording();
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpChat(WidgetTester tester) async {
    shell = NeuraShellState();
    addTearDown(shell.dispose);
    await tester.pumpWidget(NeuraShellScope(
      notifier: shell,
      child: const MaterialApp(home: NeuraChatScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> startListening(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Talk freely (hands-free)'));
    // Subscription cancellation can complete outside the widget test clock.
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(NeuraSpeechToTextService.instance.isListening, isTrue,
        reason: 'Native calls: $calls');
  }

  Future<void> say(WidgetTester tester, String phrase) async {
    await startListening(tester);
    await native('onFinal', phrase);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'only completed speech changes mode and consumes the local command',
      (tester) async {
    await pumpChat(tester);
    expect(calls, isEmpty);
    await startListening(tester);
    await native('onPartial', 'Neura, coach mode');
    await tester.pump();
    expect(find.byTooltip('Conversation mode: Balanced'), findsOneWidget);

    await native('onFinal', 'Neura, coach mode');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Conversation mode: Coach'), findsOneWidget);
    expect(find.text('Neura, coach mode'), findsNothing);
    expect(calls, ['start', 'stop']);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);

    await native('onFinal', 'Neura, open mood');
    await tester.pumpAndSettle();
    expect(find.byType(MoodCheckInScreen), findsNothing);
    expect(calls, ['start', 'stop']);
  });

  testWidgets('opens an existing local screen after stopping the microphone',
      (tester) async {
    await pumpChat(tester);
    await say(tester, 'Hey Neura, open mood check in');
    expect(find.byType(MoodCheckInScreen), findsOneWidget);
    expect(calls, ['start', 'stop']);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);

    Navigator.of(tester.element(find.byType(MoodCheckInScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Talk freely (hands-free)'), findsOneWidget);
    expect(calls, ['start', 'stop']);
    expect(find.text('Hey Neura, open mood check in'), findsNothing);
  });

  testWidgets('room commands navigate locally and report the current room',
      (tester) async {
    await pumpChat(tester);
    expect(shell.room.id, NeuraRoom.penthouse.id);

    await say(tester, 'Neura, open dream room');
    expect(shell.room.id, NeuraRoom.dreamAtrium.id);
    expect(find.text('Dream Atrium opened.'), findsOneWidget);
    expect(find.text('Neura, open dream room'), findsNothing);

    await say(tester, 'Neura, where are we');
    expect(find.text('You are in Dream Atrium.'), findsOneWidget);
    expect(shell.room.id, NeuraRoom.dreamAtrium.id);
    expect(calls, ['start', 'stop', 'start', 'stop']);
  });

  testWidgets('mute and unmute keep the saved reply-speech policy',
      (tester) async {
    await NeuraTtsService.instance
        .setReplySpeechMode(NeuraReplySpeechMode.afterComplete);
    await pumpChat(tester);
    await say(tester, 'Neura, mute replies');
    expect(find.byTooltip('Unmute Neura'), findsOneWidget);
    expect(NeuraTtsService.instance.replySpeechMode,
        NeuraReplySpeechMode.afterComplete);

    await say(tester, 'Neura, unmute replies');
    expect(find.byTooltip('Mute Neura'), findsOneWidget);
    expect(NeuraTtsService.instance.replySpeechMode,
        NeuraReplySpeechMode.afterComplete);
  });

  testWidgets('unmute cannot turn on globally disabled reply speech',
      (tester) async {
    await pumpChat(tester);
    await say(tester, 'Neura, unmute');
    expect(NeuraTtsService.instance.replySpeechMode, NeuraReplySpeechMode.off);
    expect(find.text('Enable reply speech in Voice settings first.'),
        findsOneWidget);
    expect(find.byTooltip('Reply speech is off in Voice settings'),
        findsOneWidget);
  });

  testWidgets('Safe Mode during recognition stop cancels the command',
      (tester) async {
    await pumpChat(tester);
    await startListening(tester);
    stopGate = Completer<void>();
    await native('onFinal', 'Neura, coach mode');
    await tester.pump();
    expect(calls, ['start', 'stop']);

    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Conversation mode: Balanced'), findsOneWidget);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
    final mic = tester.widget<IconButton>(find.byWidgetPredicate(
      (widget) =>
          widget is IconButton && widget.tooltip == 'Talk freely (hands-free)',
    ));
    expect(mic.onPressed, isNull);
    expect(calls, ['start', 'stop']);
  });

  testWidgets('ending a session discards a late command while stop is pending',
      (tester) async {
    await pumpChat(tester);
    await startListening(tester);
    stopGate = Completer<void>();
    await tester.tap(find.byTooltip('End hands-free conversation'));
    await tester.pump();
    await native('onFinal', 'Neura, open mood');
    await tester.pump();
    stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MoodCheckInScreen), findsNothing);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
    expect(calls, ['start', 'stop']);
  });

  testWidgets(
      'backgrounding stops capture and does not resume it automatically',
      (tester) async {
    await pumpChat(tester);
    await startListening(tester);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await native('onFinal', 'Neura, open mood');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(MoodCheckInScreen), findsNothing);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
    expect(calls, ['start', 'stop']);
  });

  testWidgets('voice help is discoverable and never starts recording',
      (tester) async {
    await pumpChat(tester);
    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice commands'));
    await tester.pumpAndSettle();
    expect(find.text('“Neura, stop listening”'), findsOneWidget);
    expect(calls, isEmpty);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
  });
}
