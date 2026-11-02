import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/integrations/tts/neura_windows_tts.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';
import 'package:neuro_companion/avatar/avatar_controller.dart';
import 'package:neuro_companion/avatar/avatar_orchestrator.dart';
import 'package:neuro_companion/avatar/avatar_orchestrator_viseme_ext.dart';
import 'package:neuro_companion/avatar/avatar_rive_inputs.dart';
import 'package:neuro_companion/core/neura_event_bus.dart';
import 'package:neuro_companion/core/neura_events.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';
import 'package:neuro_companion/modules/chat/neura_chat_screen.dart';
import 'package:neuro_companion/modules/core/app_log.dart';
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/neura_link/local_conversation_session.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_speech_to_text_service.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/services/wake_word_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

// The same real chat/ASR/Ollama/TTS flow runs independently on #157 and on
// the pinned disposable #157 + #158 + #149 source combination in CI. Only
// the combined run requires native viseme delivery, which belongs to #158.
const _nativeVisemes = bool.fromEnvironment('NEURA_VALIDATE_NATIVE_VISEMES');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const asr = MethodChannel('neura/speech_recognition');
  const sapi = MethodChannel('neura/speech_synthesis');
  const engine = MethodChannel('neura/engine_synthetic_session');
  const rust = MethodChannel('neura/local_conversation');
  var rustSnapshot = <String, Object>{'state': 'idle'};
  const codec = StandardMethodCodec();
  final events = <Object>[];
  final payloads = <Map<String, dynamic>>[];
  final nativeCalls = <String>[];
  Completer<void>? asrStop;
  Completer<void>? speechStop;
  Completer<Object?>? oldSpeechPoll;
  String? modelReply;
  var speechState = 'speaking';
  var viseme = 21;
  var speechId = 0;
  var modelId = 0;
  late NeuraAiService ai;
  late NeuraOllamaChat ollama;
  late NeuraTtsService tts;
  late AvatarController avatar;
  late AvatarOrchestrator orchestrator;
  late AvatarVisemeWiring wiring;

  void record(Object event) {
    if (event is NeuraListeningEvent ||
        event is NeuraThinkingEvent ||
        event is NeuraTalkingEvent ||
        event is NeuraMouthOpenEvent ||
        event is NeuraVisemeEvent) {
      events.add(event);
    }
  }

  List<String> phases() => events
      .where(
        (e) =>
            e is NeuraListeningEvent ||
            e is NeuraThinkingEvent ||
            e is NeuraTalkingEvent,
      )
      .map(
        (e) => switch (e) {
          NeuraListeningEvent() => 'listen:${e.isListening}',
          NeuraThinkingEvent() => 'think:${e.isThinking}',
          NeuraTalkingEvent() => 'talk:${e.isTalking}',
          _ => throw StateError('Unexpected phase'),
        },
      )
      .toList();

  Future<void> native(String method, [String? text]) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      asr.name,
      codec.encodeMethodCall(MethodCall(method, text)),
      (_) {},
    );
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    // Keep this isolated test process off the filesystem. Log durability is
    // covered separately; only presentation and owned native channels run here.
    await AppLog.instance.resetAfterDataWipe();
  });

  setUp(() async {
    SafeBoot.instance.safeMode.value = false;
    WakeWordPrefsController.instance.enabled.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NeuraPrefsCache.prefs.clear();
    ollama = NeuraOllamaChat(supported: true);
    ai = NeuraAiService.forTesting(
      modelRouter: NeuraSecureModelRouter(),
      configuredReader: () => false,
      ollama: ollama,
    );
    tts = NeuraTtsService.forTesting(NeuraWindowsTts());
    await tts.setReplySpeechMode(
      NeuraReplySpeechMode.afterComplete,
    );
    rustSnapshot = {'state': 'idle'};
    events.clear();
    payloads.clear();
    nativeCalls.clear();
    modelReply = null;
    asrStop = speechStop = null;
    oldSpeechPoll = null;
    speechState = 'speaking';
    viseme = 21;
    NeuraEventBus.I.onAny(record);
    avatar = AvatarController();
    orchestrator = AvatarOrchestrator(controller: avatar, bus: NeuraEventBus.I)
      ..start();
    wiring = AvatarVisemeWiring(controller: avatar, bus: NeuraEventBus.I)
      ..start();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(asr, (call) async {
      nativeCalls.add('asr:${call.method}');
      if (call.method == 'stop') {
        if (asrStop != null) await asrStop!.future;
        await native('onStopped');
      }
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(sapi, (call) async {
      nativeCalls.add('sapi:${call.method}');
      if (call.method == 'getVoices') return <dynamic>[];
      if (call.method == 'speak') {
        speechId = (call.arguments as Map)['id'] as int;
      }
      if (call.method == 'stop' && speechStop != null) await speechStop!.future;
      if (call.method == 'poll') {
        final gate = oldSpeechPoll;
        if (gate != null) return gate.future;
        return {'id': speechId, 'state': speechState, 'viseme': viseme};
      }
      return 1;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(engine, (
      call,
    ) async {
      nativeCalls.add('engine:${call.method}');
      if (call.method == 'beginOllama') {
        payloads.add(
          jsonDecode(call.arguments as String) as Map<String, dynamic>,
        );
        return ++modelId;
      }
      if (call.method == 'pollOllama') return modelReply;
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(rust, (call) async {
      nativeCalls.add('rust:${call.method}');
      return switch (call.method) {
        'start' => 'idle',
        'send' => true,
        'poll' => rustSnapshot,
        _ => null,
      };
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async {
        fail(
          'Owned Windows speech must not call the legacy plugin: ${call.method}',
        );
      },
    );
  });

  tearDown(() async {
    for (final gate in [asrStop, speechStop]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    if (oldSpeechPoll != null && !oldSpeechPoll!.isCompleted) {
      oldSpeechPoll!.complete({'id': speechId, 'state': 'cancelled'});
    }
    oldSpeechPoll = null;
    await NeuraSpeechToTextService.instance.stopRecording();
    await tts.stop();
    NeuraEventBus.I.offAny(record);
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (final channel in [
      asr,
      sapi,
      engine,
      const MethodChannel('flutter_tts'),
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> chat(WidgetTester tester, {bool rustSession = false}) async {
    final shell = NeuraShellState();
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      NeuraShellScope(
        notifier: shell,
        child: MaterialApp(
            home: NeuraChatScreen(
                aiService: ai,
                ttsService: tts,
                localSession:
                    LocalConversationSession(supported: rustSession))),
      ),
    );
    await tester.pumpAndSettle();
    if (rustSession) return;
    await tester.tap(find.byTooltip('Approved cloud / basic local reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline Ollama'));
    await tester.pumpAndSettle();
    events.clear();
  }

  Future<void> drain(WidgetTester tester) async {
    // Advance both the platform/plugin microtasks and frame-batched reply
    // delivery. Do not await the fake clock's logging queue from runAsync.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> ask(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextField),
      'Synthetic private question',
    );
    await tester.tap(find.byTooltip('Send'));
    await drain(tester);
    expect(phases(), contains('think:true'));
    expect(payloads, hasLength(1), reason: '${phases()} calls=$nativeCalls');
  }

  Future<void> answer(WidgetTester tester) async {
    modelReply = 'Synthetic local answer.';
    await tester.pump(const Duration(milliseconds: 120));
    await drain(tester);
    expect(nativeCalls, contains('sapi:speak'),
        reason:
            '${phases()} mode=${tts.replySpeechMode} allowed=${tts.playbackAllowed}');
    expect(
      phases().indexOf('think:false'),
      lessThan(phases().indexOf('talk:true')),
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await drain(tester);
  }

  void conversationTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body(tester);
      } finally {
        for (final gate in [asrStop, speechStop]) {
          if (gate != null && !gate.isCompleted) gate.complete();
        }
        if (oldSpeechPoll != null && !oldSpeechPoll!.isCompleted) {
          oldSpeechPoll!.complete({'id': speechId, 'state': 'cancelled'});
        }
        oldSpeechPoll = null;
        speechStop = null;
        await close(tester);
        ollama.dispose();
        final ending = tts.dispose();
        await tester.pump();
        await ending;
        orchestrator.dispose();
        wiring.stop();
        avatar.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  conversationTest(
    'microphone, thinking, first answer, speech and rest (native visemes: $_nativeVisemes)',
    (tester) async {
      await chat(tester);
      await tester.tap(find.byTooltip('Talk freely (hands-free)'));
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();
      expect(phases(), ['listen:true']);
      expect(avatar.signals.isListening, isTrue);
      await native('onPartial', 'Synthetic private transcript');
      await tester.pump();
      expect(phases(), ['listen:true']);
      await native('onFinal', 'Synthetic private question');
      await drain(tester);
      expect(phases().take(3), ['listen:true', 'listen:false', 'think:true']);
      await answer(tester);
      expect(avatar.signals.isThinking, isFalse);
      expect(avatar.signals.isTalking, isTrue);
      if (_nativeVisemes) {
        expect(
          events.whereType<NeuraVisemeEvent>().last.viseme,
          NeuraViseme.MBP,
        );
        expect(events.whereType<NeuraMouthOpenEvent>().last.open, 0);
        expect(
            avatar.numberInput(AvatarRiveInputs.viseme), NeuraViseme.MBP.index);
        expect(avatar.numberInput(AvatarRiveInputs.mouthOpen), 0);
        viseme = 3;
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          events.whereType<NeuraMouthOpenEvent>().last.open,
          greaterThan(0),
        );
      }
      speechState = 'completed';
      await tester.pump(const Duration(milliseconds: 40));
      await drain(tester);
      expect(
        phases(),
        containsAllInOrder([
          'think:false',
          'talk:true',
          'talk:false',
          'listen:true',
        ]),
      );
      await tester.tap(find.byTooltip('End hands-free conversation'));
      await drain(tester);
      expect(events.whereType<NeuraListeningEvent>().last.isListening, isFalse);
      expect(
        events.whereType<NeuraVisemeEvent>().last.viseme,
        NeuraViseme.rest,
      );
      expect(avatar.signals.isTalking, isFalse);
      expect(avatar.signals.isThinking, isFalse);
      expect(avatar.numberInput(AvatarRiveInputs.mouthOpen), 0);
      // Assert the entire emitted presentation schema, rather than toString():
      // every public value is a bool, bounded number or mouth-shape enum.
      for (final e in events) {
        expect(
          e,
          anyOf(
            isA<NeuraListeningEvent>(),
            isA<NeuraThinkingEvent>(),
            isA<NeuraTalkingEvent>(),
            isA<NeuraMouthOpenEvent>(),
            isA<NeuraVisemeEvent>(),
          ),
        );
      }
      expect(payloads.single.keys.toSet(), {'system', 'messages'});
      expect((payloads.single['messages'] as List).last, {
        'role': 'user',
        'content': 'Synthetic private question',
      });
      await close(tester);
    },
  );

  conversationTest(
    'background clears thinking before native speech stop acknowledges',
    (tester) async {
      await chat(tester);
      await ask(tester);
      asrStop = Completer<void>();
      speechStop = Completer<void>();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(phases().last, 'think:false');
      modelReply = 'Synthetic stale answer';
      await drain(tester);
      expect(nativeCalls, isNot(contains('sapi:speak')));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(phases().last, 'think:false');
      asrStop!.complete();
      speechStop!.complete();
      await drain(tester);
      expect(find.text('Synthetic stale answer'), findsNothing);
      await close(tester);
    },
  );

  conversationTest(
    'Safe Mode exit and rebuild do not revive a cancelled generation',
    (tester) async {
      await chat(tester);
      await ask(tester);
      speechStop = Completer<void>();
      SafeBoot.instance.safeMode.value = true;
      expect(phases().last, 'think:false');
      SafeBoot.instance.safeMode.value = false;
      await tester.tap(find.byTooltip('Conversation mode: Balanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quiet'));
      await tester.pump();
      expect(phases().last, 'think:false');
      modelReply = 'Synthetic stale answer';
      speechStop!.complete();
      await drain(tester);
      expect(find.text('Synthetic stale answer'), findsNothing);
      expect(nativeCalls, isNot(contains('sapi:speak')));
      await close(tester);
    },
  );

  conversationTest(
    'interruption revokes the turn before native speech stop acknowledges',
    (tester) async {
      await chat(tester);
      await ask(tester);
      speechStop = Completer<void>();
      await tester.tap(find.byTooltip('Stop offline reply'));
      await tester.pump();
      expect(phases().last, 'think:false');
      modelReply = 'Synthetic stale answer';
      await drain(tester);
      expect(nativeCalls, isNot(contains('sapi:speak')));
      speechStop!.complete();
      await drain(tester);
      await close(tester);
    },
  );

  conversationTest(
    'late native viseme after background and foreground cannot reopen the mouth',
    (tester) async {
      await chat(tester);
      await ask(tester);
      await answer(tester);
      oldSpeechPoll = Completer<Object?>();
      await tester.pump(const Duration(milliseconds: 40));
      final oldId = speechId;
      speechStop = Completer<void>();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final count = events.length;
      oldSpeechPoll!.complete({'id': oldId, 'state': 'speaking', 'viseme': 3});
      await tester.pump();
      expect(events.length, count);
      speechStop!.complete();
      oldSpeechPoll = null;
      await drain(tester);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await drain(tester);
      expect(
        events.whereType<NeuraVisemeEvent>().last.viseme,
        NeuraViseme.rest,
      );
      expect(phases().last, 'talk:false');
      await close(tester);
    },
  );
  conversationTest('model cancellation clears thinking without speaking',
      (tester) async {
    await chat(tester);
    await ask(tester);
    ai.cancelActiveGeneration();
    await drain(tester);
    expect(events.whereType<NeuraThinkingEvent>().last.isThinking, isFalse);
    expect(
        events.whereType<NeuraTalkingEvent>().any((e) => e.isTalking), isFalse);
    expect(nativeCalls, contains('engine:cancelOllama'));
  });

  conversationTest(
      'microphone background and recovery discard late transcripts',
      (tester) async {
    await chat(tester);
    await tester.tap(find.byTooltip('Talk freely (hands-free)'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(events.whereType<NeuraListeningEvent>().last.isListening, isTrue);
    asrStop = Completer<void>();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(events.whereType<NeuraListeningEvent>().last.isListening, isFalse);
    await native('onFinal', 'Synthetic stale transcript');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(payloads, isEmpty);
    asrStop!.complete();
    await drain(tester);
    expect(find.text('Synthetic stale transcript'), findsNothing);
    expect(nativeCalls.where((c) => c == 'asr:start'), hasLength(1));
    await tester.tap(find.byTooltip('Talk freely (hands-free)'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(nativeCalls.where((c) => c == 'asr:start'), hasLength(2));
  });

  conversationTest(
      'Rust adapter text-only grant emits thinking and never starts voice or Ollama',
      (tester) async {
    await chat(tester, rustSession: true);
    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline text chat (preview)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start offline chat'));
    await tester.pumpAndSettle();
    events.clear();
    await tester.enterText(find.byType(TextField), 'Synthetic Rust question');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(events.whereType<NeuraThinkingEvent>().last.isThinking, isTrue);
    rustSnapshot = {'state': 'idle', 'text': 'Synthetic Rust answer'};
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('Synthetic Rust answer'), findsOneWidget);
    expect(events.whereType<NeuraThinkingEvent>().last.isThinking, isFalse);
    expect(nativeCalls, contains('rust:send'));
    expect(nativeCalls, isNot(contains('sapi:speak')));
    expect(nativeCalls, isNot(contains('asr:start')));
    expect(payloads, isEmpty);
  });
  conversationTest(
      'approval dialogs retain the turn while opaque route coverage cancels it',
      (tester) async {
    await chat(tester);
    await ask(tester);
    final context = tester.element(find.byType(NeuraChatScreen));
    final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Synthetic approval')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(avatar.signals.isThinking, isTrue);
    expect(nativeCalls, isNot(contains('engine:cancelOllama')));
    Navigator.of(tester.element(find.text('Synthetic approval'))).pop();
    await dialog;
    await tester.pump();
    final covering = Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) =>
            const Scaffold(body: Text('Synthetic covering route'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await drain(tester);
    expect(avatar.signals.isThinking, isFalse);
    expect(nativeCalls, contains('engine:cancelOllama'));
    modelReply = 'Synthetic covered stale answer';
    Navigator.of(tester.element(find.text('Synthetic covering route'))).pop();
    await covering;
    await drain(tester);
    expect(find.text('Synthetic covered stale answer'), findsNothing);
    expect(avatar.signals.isThinking, isFalse);
    expect(avatar.signals.isListening, isFalse);
  });
}
