import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_model_stream.dart';
import 'package:neuro_companion/services/neura_model_types.dart';

void main() {
  test('Anthropic default is Opus 5.5 with explicit effort and fallbacks', () {
    expect(kNeuraAnthropicModel, 'claude-opus-5-5');
    expect(kNeuraAnthropicDefaultProfile.model, kNeuraAnthropicModel);
    expect(kNeuraAnthropicEffort, 'medium');
    expect(kNeuraAnthropicFallbacks, 'default');
    expect(kNeuraAnthropicFallbackBeta, 'server-side-fallback-2026-07-01');
  });

  test('blocks without a fallback are echoed unchanged', () {
    final blocks = [
      {'type': 'thinking', 'thinking': '', 'signature': 's'},
      {'type': 'text', 'text': 'Hi'},
      {'type': 'tool_use', 'id': 't1', 'name': 'x', 'input': {}},
    ];
    expect(NeuraModelStreamTransport.echoableAnthropicBlocks(blocks), blocks);
  });

  test('pre-fallback thinking and tool calls are dropped, boundary kept', () {
    final blocks = [
      {'type': 'thinking', 'thinking': '', 'signature': 'a'},
      {'type': 'text', 'text': 'Partial '},
      {'type': 'tool_use', 'id': 't1', 'name': 'x', 'input': {}},
      {
        'type': 'fallback',
        'from': {'model': 'claude-opus-5-5'},
        'to': {'model': 'claude-opus-5'},
      },
      {'type': 'thinking', 'thinking': '', 'signature': 'b'},
      {'type': 'tool_use', 'id': 't2', 'name': 'x', 'input': {}},
    ];
    expect(
      NeuraModelStreamTransport.echoableAnthropicBlocks(
        blocks,
      ).map((b) => b['type']),
      ['text', 'fallback', 'thinking', 'tool_use'],
    );
  });
}
