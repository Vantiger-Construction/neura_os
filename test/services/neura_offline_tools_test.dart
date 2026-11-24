import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';

void main() {
  test('tool envelope parses calls and rejects anything unexpected', () {
    final turn = NeuraOllamaTurn.parse(jsonEncode({
      'text': 'Saving that.',
      'tool_calls': [
        {
          'name': 'log_mood_entry',
          'arguments': {'mood0to10': 7},
        },
      ],
    }));
    expect(turn.text, 'Saving that.');
    expect(turn.toolCalls.single.name, 'log_mood_entry');
    expect(turn.toolCalls.single.arguments, {'mood0to10': 7});
    for (final bad in [
      'plain text',
      jsonEncode({'text': 'x'}),
      jsonEncode({'text': 'x', 'tool_calls': [], 'extra': 1}),
      jsonEncode({
        'text': 'x',
        'tool_calls': [
          {'name': '../run', 'arguments': {}},
        ],
      }),
      jsonEncode({
        'text': 'x',
        'tool_calls': [
          {'name': 'set_tone', 'arguments': 'calm'},
        ],
      }),
    ]) {
      expect(() => NeuraOllamaTurn.parse(bad), throwsFormatException);
    }
  });

  test('long tool results keep the newest whole lines', () {
    final lines = [for (var i = 0; i < 100; i++) 'day $i: mood 5/10'];
    final result = NeuraOllamaTurn.boundToolResult(lines.join('\n'));
    expect(utf8.encode(result).length, lessThanOrEqualTo(1500));
    expect(result.split('\n').last, 'day 99: mood 5/10');
    expect(result.split('\n').every(lines.contains), isTrue);
    expect(NeuraOllamaTurn.boundToolResult('short'), 'short');
  });

  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/engine_synthetic_session');

  testWidgets('advertised tools are sent to the native request', (
    tester,
  ) async {
    Map<String, dynamic>? request;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'beginOllama') {
        request = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        return 5;
      }
      if (call.method == 'pollOllama') {
        return jsonEncode({'text': 'Done.', 'tool_calls': []});
      }
      return null;
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final chat = NeuraOllamaChat(supported: true);
    addTearDown(chat.dispose);
    const tool = {
      'name': 'set_tone',
      'description': 'Set tone.',
      'parameters': {'type': 'object'},
    };
    final raw = await chat.reply(
      system: 'Neura charter',
      messages: [
        {'role': 'user', 'content': 'Be calmer'},
      ],
      cancel: NeuraGenerationCancel('tools'),
      tools: const [tool],
    );
    expect(request!['tools'], [tool]);
    expect(NeuraOllamaTurn.parse(raw).text, 'Done.');
  });
}
