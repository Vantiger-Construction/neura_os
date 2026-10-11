import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/modules/chat/neura_chat_screen.dart';
import 'package:neuro_companion/neura_link/local_conversation_session.dart';
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/services/wake_word_prefs.dart';
import 'package:neuro_companion/startup/neura_error_pipeline.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const local = MethodChannel('neura/local_conversation');
  const speech = MethodChannel('neura/speech_recognition');
  late List<MethodCall> calls;
  late List<String> speechCalls;
  late Map<String, Object> snapshot;
  late NeuraShellState shell;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    calls = [];
    speechCalls = [];
    snapshot = {'state': 'idle'};
    SafeBoot.instance.safeMode.value = false;
    NeuraErrorPipeline.instance.clearFatalError();
    WakeWordPrefsController.instance.enabled.value = false;
    await NeuraTtsService.instance.setReplySpeechMode(NeuraReplySpeechMode.off);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(local, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'start' => 'idle',
        'send' => true,
        'poll' => snapshot,
        _ => null,
      };
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(speech, (
      call,
    ) async {
      speechCalls.add(call.method);
      return null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(local, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(speech, null);
    SafeBoot.instance.safeMode.value = false;
    NeuraErrorPipeline.instance.clearFatalError();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  Future<void> pumpChat(WidgetTester tester, {bool supported = true}) async {
    shell = NeuraShellState();
    addTearDown(shell.dispose);
    final session = LocalConversationSession(supported: supported);
    await tester.pumpWidget(
      NeuraShellScope(
        notifier: shell,
        child: MaterialApp(home: NeuraChatScreen(localSession: session)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseOffline(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline text chat (preview)'));
    await tester.pumpAndSettle();
    expect(find.text('Start offline text chat?'), findsOneWidget);
    await tester.tap(find.text('Start offline chat'));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
  }

  testWidgets('feature is unavailable on unsupported builds', (tester) async {
    await pumpChat(tester, supported: false);
    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    expect(find.text('Offline text chat (preview)'), findsNothing);
    expect(calls, isEmpty);
    await close(tester);
  });

  testWidgets(
    'explicit selection clears earlier drafts and gates other inputs',
    (tester) async {
      await pumpChat(tester);
      await tester.enterText(find.byType(TextField), 'earlier private draft');
      expect(calls, isEmpty);
      await chooseOffline(tester);
      expect(calls.where((c) => c.method == 'start').length, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      for (final tooltip in [
        'Select text for the next reply',
        'Attach a photo',
        'Talk freely (hands-free)',
      ]) {
        expect(
          tester.widget<IconButton>(find.byTooltip(tooltip)).onPressed,
          isNull,
        );
      }
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      expect(speechCalls.where((method) => method == 'start'), isEmpty);
      await close(tester);
    },
  );

  testWidgets(
    'typed conversation renders locally without cloud preparation or tools',
    (tester) async {
      await pumpChat(tester);
      await chooseOffline(tester);
      final attempts = NeuraAiService.instance.diagnosticsSnapshot['attempts'];
      final generation = NeuraAiService.instance.activeGenerationId;
      final room = shell.room;
      snapshot = {
        'state': 'idle',
        'text': 'Open room is plain model text, not an action.',
      };
      await send(tester, 'Help me plan dinner.');
      expect(
        find.text('Open room is plain model text, not an action.'),
        findsOneWidget,
      );
      expect(
        calls.singleWhere((c) => c.method == 'send').arguments,
        'Help me plan dinner.',
      );
      expect(NeuraAiService.instance.diagnosticsSnapshot['attempts'], attempts);
      expect(NeuraAiService.instance.activeGenerationId, generation);
      expect(shell.room, room);
      expect(find.textContaining("Hi. I'm Neura."), findsNothing);
      await close(tester);
      expect(calls.last.method, 'stop');
    },
  );

  testWidgets('local error keeps offline selected and never uses a fallback', (
    tester,
  ) async {
    await pumpChat(tester);
    await chooseOffline(tester);
    final attempts = NeuraAiService.instance.diagnosticsSnapshot['attempts'];
    snapshot = {'state': 'error'};
    await send(tester, 'Help with my day.');
    expect(find.textContaining('Offline text · error'), findsOneWidget);
    expect(find.text('Help with my day.'), findsNothing);
    expect(NeuraAiService.instance.diagnosticsSnapshot['attempts'], attempts);
    expect(calls.where((c) => c.method == 'send').length, 1);
    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    expect(find.text('Use standard chat'), findsOneWidget);
    await close(tester);
  });

  testWidgets('background clears session text and does not restart on return', (
    tester,
  ) async {
    await pumpChat(tester);
    await chooseOffline(tester);
    snapshot = {'state': 'idle', 'text': 'local reply'};
    await send(tester, 'session-only words');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('session-only words'), findsNothing);
    expect(find.text('local reply'), findsNothing);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'start').length, 1);
    expect(find.textContaining('Offline text · disabled'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'explicit crisis language uses existing static support without inference',
    (tester) async {
      await pumpChat(tester);
      await chooseOffline(tester);
      await send(tester, 'I want to die');
      expect(calls.any((c) => c.method == 'send'), isFalse);
      expect(
        find.textContaining('Feeling Very Unsafe or In Danger'),
        findsOneWidget,
      );
      expect(find.text('Help me through this'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('visible offline history stays within eight messages', (
    tester,
  ) async {
    await pumpChat(tester);
    await chooseOffline(tester);
    for (var i = 0; i < 6; i++) {
      snapshot = {'state': 'idle', 'text': 'answer $i'};
      await send(tester, 'question $i');
    }
    final list = tester.widget<ListView>(find.byType(ListView));
    expect((list.childrenDelegate as SliverChildBuilderDelegate).childCount, 8);
    await close(tester);
  });
}
