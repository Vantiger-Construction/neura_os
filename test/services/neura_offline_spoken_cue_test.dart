import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/core/app_log.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';
import 'package:neuro_companion/services/neura_language.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_offline_prompt.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the system prompt and per-turn cue handed to the on-device model.
class _CapturingOllama extends NeuraOllamaChat {
  _CapturingOllama() : super(supported: true);
  final systems = <String>[];
  final cues = <String>[];
  var warms = 0;

  @override
  Future<void> warm({
    required String system,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    warms++;
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
    cues.add(cue);
    return tools.isEmpty
        ? 'Synthetic offline reply.'
        : jsonEncode({'text': 'Synthetic offline reply.', 'tool_calls': []});
  }
}

const _stressed =
    "I have three deadlines tomorrow and I don't know where to start";

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

  const turn = [NeuraChatTurn(isUser: true, text: 'Is camera hawk on')];

  test('a spoken turn tells the model to answer the likely meaning', () async {
    await ai.streamReply(turn, localOllama: true, newestSpoken: true).join();
    final cue = ollama.cues.single;
    expect(cue, contains('aloud'));
    expect(cue, contains('one short question'));
    expect(
      utf8.encode(cue).length,
      lessThanOrEqualTo(NeuraOllamaChat.maxCueBytes),
    );
    // The per-turn note never enters the system prompt, so the local model
    // keeps reusing its cached evaluation between turns.
    expect(ollama.systems.single, endsWith(kNeuraOfflineSystemSuffix));
    expect(ollama.systems.single, isNot(contains(cue)));
  });

  test('typed turns are unchanged', () async {
    await ai.streamReply(turn, localOllama: true).join();
    expect(ollama.cues.single, isNot(contains('aloud')));
  });

  test('the spoken note keeps a clear emotion cue alongside it', () async {
    const mood = [NeuraChatTurn(isUser: true, text: _stressed)];
    await ai.streamReply(mood, localOllama: true, newestSpoken: true).join();
    final cue = ollama.cues.single;
    expect(cue, contains('aloud'));
    expect(cue, contains('Likely mood: very overwhelmed.'));
  });

  test('a Spanish turn asks for a Spanish reply, ahead of other notes',
      () async {
    const spanish = [
      NeuraChatTurn(isUser: true, text: 'Estoy muy cansado y necesito ayuda'),
    ];
    await ai
        .streamReply(
          spanish,
          localOllama: true,
          newestSpoken: true,
          replyLanguage: NeuraLanguage.es,
        )
        .join();
    final cue = ollama.cues.single;
    expect(cue, startsWith('They are speaking Spanish.'));
    expect(cue, contains('aloud'));
    expect(
      utf8.encode(cue).length,
      lessThanOrEqualTo(NeuraOllamaChat.maxCueBytes),
    );
    expect(ollama.systems.single, isNot(contains('Spanish')));
  });

  test('English turns carry no language note', () async {
    await ai
        .streamReply(turn, localOllama: true, replyLanguage: NeuraLanguage.en)
        .join();
    expect(ollama.cues.single, isNot(contains('They are speaking')));
  });
}
