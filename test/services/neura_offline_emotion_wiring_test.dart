import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/core/app_log.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/emotion_analysis_service.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_offline_budget.dart';
import 'package:neuro_companion/services/neura_offline_prompt.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';
import 'package:neuro_companion/src/modules/focus/focus_controller.dart';
import 'package:neuro_companion/src/modules/focus/focus_mode.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records exactly what NeuraAiService hands the on-device model.
class _CapturingOllama extends NeuraOllamaChat {
  _CapturingOllama() : super(supported: true);
  final systems = <String>[];
  final sent = <List<Map<String, dynamic>>>[];
  final cues = <String>[];
  final tools = <List<Map<String, dynamic>>>[];
  final maxTokens = <int?>[];
  final warmed = <({String system, List<Map<String, dynamic>> tools})>[];

  @override
  Future<void> warm({
    required String system,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    warmed.add((system: system, tools: tools));
  }

  @override
  Future<String> reply({
    required String system,
    required List<Map<String, dynamic>> messages,
    required NeuraGenerationCancel cancel,
    void Function(String textSoFar)? onPartial,
    List<Map<String, dynamic>> tools = const [],
    String cue = '',
    int? maxTokens,
  }) async {
    systems.add(system);
    sent.add(messages);
    cues.add(cue);
    this.tools.add(tools);
    this.maxTokens.add(maxTokens);
    return tools.isEmpty
        ? 'Synthetic offline reply.'
        : jsonEncode({'text': 'Synthetic offline reply.', 'tool_calls': []});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _CapturingOllama ollama;
  late NeuraAiService ai;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await AppLog.instance.resetAfterDataWipe();
  });

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    ollama = _CapturingOllama();
    ai = NeuraAiService.forTesting(
      modelRouter: NeuraSecureModelRouter(),
      configuredReader: () => false,
      ollama: ollama,
    );
  });

  /// Returns the per-turn cue sent alongside the newest turn.
  Future<String> send(
    List<NeuraChatTurn> history, {
    NeuraOfflineBudget budget = NeuraOfflineBudget.standard,
  }) async {
    await ai
        .streamReply(history, localOllama: true, offlineBudget: budget)
        .join();
    expect(ollama.systems, hasLength(1));
    // The system prompt never carries the per-turn cue, so it stays identical
    // between turns and the local model reuses its cached evaluation.
    expect(ollama.systems.single, endsWith(kNeuraOfflineSystemSuffix));
    return ollama.cues.single;
  }

  test('a clear feeling adds one tentative cue after the newest turn',
      () async {
    final cue = await send(const [
      NeuraChatTurn(
          isUser: true,
          text:
              "I have three deadlines tomorrow and I don't know where to start"),
    ]);
    expect(
        cue, 'Likely mood: very overwhelmed. Respond to it without naming it.');
    expect(utf8.encode(ollama.systems.single).length, lessThanOrEqualTo(6500));
    expect(
      utf8.encode(cue).length,
      lessThanOrEqualTo(NeuraOllamaChat.maxCueBytes),
    );
  });

  test('the system prompt is identical whatever the mood', () async {
    await ai.streamReply(const [
      NeuraChatTurn(
          isUser: true,
          text:
              "I have three deadlines tomorrow and I don't know where to start"),
    ], localOllama: true).join();
    await ai.streamReply(const [
      NeuraChatTurn(isUser: true, text: 'How long should I boil an egg?'),
    ], localOllama: true).join();
    expect(ollama.systems, hasLength(2));
    expect(ollama.systems.first, ollama.systems.last);
    expect(ollama.cues.first, isNotEmpty);
    expect(ollama.cues.last, isEmpty);
  });

  test('every possible cue fits the native cue limit', () {
    expect(
      EmotionRead.maxCueBytes,
      lessThanOrEqualTo(NeuraOllamaChat.maxCueBytes),
    );
  });

  test('an ordinary message sends no cue at all', () async {
    final cue = await send(const [
      NeuraChatTurn(isUser: true, text: 'How long should I boil an egg?'),
    ]);
    expect(cue, isEmpty);
  });

  test('a feeling that scrolled out of the model view is gently recalled',
      () async {
    // These exchanges exceed the compact byte budget, so the first message
    // is no longer visible to the model.
    final history = <NeuraChatTurn>[
      const NeuraChatTurn(
          isUser: true,
          text: "I'm really dreading my exam tomorrow, so nervous about it"),
      for (var i = 0; i < 5; i++) ...[
        NeuraChatTurn(isUser: false, text: 'Synthetic answer number $i. ' * 12),
        NeuraChatTurn(isUser: true, text: 'Another everyday question $i?'),
      ],
    ];
    final cue = await send(history, budget: NeuraOfflineBudget.compact);
    final visible = ollama.sent.single.map((m) => m['content']).toList();
    expect(visible, isNot(contains(history.first.text)));
    expect(cue, EmotionAnalysisService.earlierCue('anxious'));
  });

  test('a feeling still in view is left for the model to read itself',
      () async {
    final cue = await send(const [
      NeuraChatTurn(isUser: true, text: "I'm so nervous about my exam"),
      NeuraChatTurn(isUser: false, text: 'Synthetic support.'),
      NeuraChatTurn(isUser: true, text: 'Anyway, what should I cook?'),
    ]);
    expect(cue, isEmpty);
  });

  for (final withTools in [false, true]) {
    test(
        'the warm-up primes the exact prompt the next reply sends '
        '(tools: $withTools)', () async {
      for (final room in ['penthouse', 'mood_den']) {
        await ai.warmOffline(roomId: room, withTools: withTools);
        await ai.streamReply(
          const [NeuraChatTurn(isUser: true, text: 'How are you today?')],
          roomId: room,
          localOllama: true,
          onToolCommand: withTools ? (_) async => false : null,
        ).join();
        expect(ollama.warmed.last.system, ollama.systems.last, reason: room);
        expect(ollama.warmed.last.tools, ollama.tools.last, reason: room);
      }
    });
  }

  test('spoken replies forward the shorter token cap', () async {
    await ai.streamReply(
      const [NeuraChatTurn(isUser: true, text: 'How are you today?')],
      localOllama: true,
      offlineMaxTokens: NeuraOllamaChat.spokenMaxTokens,
    ).join();
    await ai.streamReply(
      const [NeuraChatTurn(isUser: true, text: 'How are you today?')],
      localOllama: true,
    ).join();
    expect(ollama.maxTokens, [NeuraOllamaChat.spokenMaxTokens, null]);
  });

  for (final mode in FocusMode.values) {
    test('a focus mode never swallows the message the user sent ($mode)',
        () async {
      await FocusController.instance.setMode(mode);
      addTearDown(() => FocusController.instance.setMode(FocusMode.off));
      final reply = await ai.streamReply(
        const [
          NeuraChatTurn(isUser: true, text: 'What should I cook tonight?')
        ],
        localOllama: true,
      ).join();
      expect(reply, 'Synthetic offline reply.');
      expect(ollama.sent.single.last['content'], 'What should I cook tonight?');
    });
  }
}
