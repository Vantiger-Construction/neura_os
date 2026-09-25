import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/modules/chat/neura_chat_screen.dart';
import 'package:neuro_companion/modules/core/app_log.dart';
import 'package:neuro_companion/modules/mood/mood_checkin_screen.dart';
import 'package:neuro_companion/modules/review/weekly_review_screen.dart';
import 'package:neuro_companion/modules/review/weekly_review_store.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/notifications/neura_notifications_prefs.dart';
import 'package:neuro_companion/notifications/notifications_settings_screen.dart';
import 'package:neuro_companion/persona/services/agent_selection_service.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_speech_to_text_service.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/services/wake_word_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/src/modules/focus/focus_controller.dart';
import 'package:neuro_companion/src/modules/focus/focus_office_screen.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/speech_recognition');
  const codec = StandardMethodCodec();
  final calls = <String>[];
  Completer<void>? stopGate;

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
    FilePicker.platform = _ContextFilePicker();
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

  Future<void> pumpChat(WidgetTester tester, {NeuraRoom? room}) async {
    final shell = NeuraShellState();
    addTearDown(shell.dispose);
    if (room != null) await shell.setRoom(room);
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
    expect(find.text('Chat controls'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('“Neura, exclude memories”'),
      350,
      scrollable: find.descendant(
          of: find.byType(BottomSheet), matching: find.byType(Scrollable)),
    );
    expect(find.text('Next reply context'), findsOneWidget);
    expect(
        find.text(
            'Uncheck memories for the next reply; saved memories stay intact.'),
        findsOneWidget);
    expect(calls, isEmpty);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
  });

  testWidgets('focus navigation waits for native stop and keeps the saved mode',
      (tester) async {
    await pumpChat(tester);
    final original = FocusController.instance.state.value;
    await startListening(tester);
    stopGate = Completer<void>();
    await native('onFinal', 'Neura, open focus office');
    await tester.pump();
    expect(find.byType(FocusOfficeScreen), findsNothing);
    stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(FocusOfficeScreen), findsOneWidget);
    expect(FocusController.instance.state.value, same(original));
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
    expect(calls, ['start', 'stop']);
  });

  testWidgets('opening weekly review does not generate or save a review',
      (tester) async {
    await pumpChat(tester);
    await say(tester, 'Neura, open weekly review');
    expect(find.byType(WeeklyReviewScreen), findsOneWidget);
    expect(find.text('No review yet'), findsOneWidget);
    expect(await WeeklyReviewStore.instance.getAll(), isEmpty);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
  });

  testWidgets('opening notifications does not enable notifications',
      (tester) async {
    await pumpChat(tester);
    final original =
        NeuraNotificationsPrefsController.instance.prefs.value.toMap();
    await say(tester, 'Neura, open notification settings');
    expect(find.byType(NotificationsSettingsScreen), findsOneWidget);
    expect(NeuraNotificationsPrefsController.instance.prefs.value.toMap(),
        original);
    expect(calls, ['start', 'stop']);
  });

  testWidgets('companion picker needs a choice and closing it leaves mic off',
      (tester) async {
    await pumpChat(tester);
    final original = AgentSelectionService.instance.explicitAgentId;
    await say(tester, 'Neura, choose a companion');
    expect(find.text('Auto'), findsOneWidget);
    expect(AgentSelectionService.instance.explicitAgentId, original);
    Navigator.of(tester.element(find.text('Auto'))).pop();
    await tester.pumpAndSettle();
    expect(AgentSelectionService.instance.explicitAgentId, original);
    expect(calls, ['start', 'stop']);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
  });

  testWidgets('context commands remove only the selected next-reply inputs',
      (tester) async {
    await pumpChat(tester);
    await tester.tap(find.byTooltip('Select text for the next reply'));
    await tester.pumpAndSettle();
    expect(find.text('Next reply: notes.txt'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);

    await say(tester, 'Neura, remove selected file');
    expect(find.text('Next reply: notes.txt'), findsNothing);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    await say(tester, 'Neura, do not use memories');
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    expect(find.text('Neura, do not use memories'), findsNothing);
    expect(find.text('Neura, remove selected file'), findsNothing);
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
  });

  testWidgets('scroll commands move through chat within its bounds',
      (tester) async {
    await pumpChat(tester, room: NeuraRoom.reflectionBay);
    expect(NeuraAiService.instance.isConfigured, isFalse);
    await tester.enterText(find.byType(TextField),
        List.filled(35, 'A line of local conversation.').join('\n'));
    // Submit outside the fake clock so the logging queue can drain normally.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Send'));
      await AppLog.instance.init();
    });
    await tester.pumpAndSettle();
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));

    await say(tester, 'Neura, go to first message');
    expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 0.1));
    await say(tester, 'Neura, page down');
    final afterDown = scroll.offset;
    expect(afterDown, greaterThan(scroll.position.minScrollExtent));
    await say(tester, 'Neura, page up');
    expect(scroll.offset, lessThan(afterDown));
    await say(tester, 'Neura, show latest message');
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 0.1));
    expect(NeuraSpeechToTextService.instance.isListening, isFalse);
  });
}

class _ContextFilePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(
            name: 'notes.txt', size: 3, readStream: Stream.value([97, 98, 99])),
      ]);
}
