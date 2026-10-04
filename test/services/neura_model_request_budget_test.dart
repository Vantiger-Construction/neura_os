import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_model_router.dart';

class _CountedJsonText {
  _CountedJsonText(this.text, this.onEncode);

  final String text;
  final void Function() onEncode;

  String toJson() {
    onEncode();
    return text;
  }
}

NeuraModelRequest requestFor(
  List<Map<String, dynamic>> messages, {
  int omittedMessageCount = 0,
}) =>
    NeuraModelRequest(
      systemPrompt: 'Be kind.',
      messages: messages,
      purpose: 'chat reply',
      includesPrivateContext: false,
      omittedMessageCount: omittedMessageCount,
    );

void main() {
  test('long history serializes only the eligible suffix and stays local', () {
    final serialized = <int>[];
    final history = [
      for (var index = 0; index < 1000; index++)
        {
          'role': 'user',
          'content': _CountedJsonText(
            'turn-$index',
            () => serialized.add(index),
          ),
        },
    ];
    final bounded = NeuraModelRequestBudget.freezeAndApply(
      requestFor(history, omittedMessageCount: 7),
    );

    expect(serialized, List.generate(48, (index) => index + 952));
    expect(bounded.messages, hasLength(48));
    expect(bounded.messages.first['content'], 'turn-952');
    expect(bounded.messages.last['content'], 'turn-999');
    expect(bounded.omittedMessageCount, 959);
    expect(history, hasLength(1000));
    expect(history.first['content'], isA<_CountedJsonText>());
  });

  test('empty and short histories keep their contents and omission counts', () {
    for (final length in [0, 1, 47, 48, 49, 60]) {
      final history = [
        for (var index = 0; index < length; index++)
          {'role': 'user', 'content': 'turn-$index'},
      ];
      final bounded = NeuraModelRequestBudget.freezeAndApply(
        requestFor(history, omittedMessageCount: 3),
      );
      final skipped = length > 48 ? length - 48 : 0;
      expect(bounded.messages, history.sublist(skipped));
      expect(bounded.omittedMessageCount, skipped + 3);
    }
  });

  test('selected nested content is detached before approval', () {
    final image = {
      'type': 'image',
      'source': {
        'type': 'base64',
        'media_type': 'image/png',
        'data': 'c3ludGhldGlj',
      },
    };
    final text = {'type': 'text', 'text': 'original text'};
    final content = <Map<String, dynamic>>[text, image];
    final history = <Map<String, dynamic>>[
      for (var index = 0; index < 60; index++)
        {'role': 'user', 'content': 'turn-$index'},
      {'role': 'user', 'content': content},
    ];
    final bounded = NeuraModelRequestBudget.freezeAndApply(requestFor(history));
    final originalPayload = jsonEncode(bounded.messages);

    text['text'] = 'replacement text';
    (image['source']! as Map)['data'] = 'replacement image';
    content.clear();
    history.last['role'] = 'assistant';
    history.clear();

    expect(jsonEncode(bounded.messages), originalPayload);
    expect(bounded.messages.last['role'], 'user');
    expect(bounded.messages.last['content'], hasLength(2));
  });

  test('count cap preserves the mandatory tool exchange and opaque replay', () {
    final replay = [
      {
        'type': 'reasoning',
        'encrypted_content': 'opaque synthetic reasoning',
      },
      {
        'type': 'function_call',
        'call_id': 'call-1',
        'name': 'get_mood_history',
        'arguments': '{"limit":1}',
      },
    ];
    final exchange = <Map<String, dynamic>>[
      {'role': 'assistant', 'content': [], 'openai_output': replay},
      {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'call-1',
            'content': 'synthetic result',
          },
        ],
      },
    ];
    final bounded = NeuraModelRequestBudget.freezeAndApply(
      requestFor([
        for (var index = 0; index < 60; index++)
          {'role': 'user', 'content': 'turn-$index'},
        ...exchange,
      ]),
    );

    expect(bounded.messages.sublist(46), exchange);
    expect(bounded.omittedMessageCount, 14);
    replay.clear();
    expect(bounded.messages[46]['openai_output'], hasLength(2));
  });

  test('text cap stops at a gap without skipping older messages', () {
    final bounded = NeuraModelRequestBudget.freezeAndApply(
      requestFor([
        for (var index = 0; index < 60; index++)
          {'role': 'user', 'content': 'turn-$index'},
        {
          'role': 'assistant',
          'content': 'x' * NeuraModelRequestBudget.maxTextCharacters,
        },
        {'role': 'user', 'content': 'latest'},
      ]),
    );

    expect(bounded.messages, [
      {'role': 'user', 'content': 'latest'},
    ]);
    expect(bounded.omittedMessageCount, 61);
  });

  test('oversized mandatory tool exchange still fails before approval', () {
    expect(
      () => NeuraModelRequestBudget.freezeAndApply(
        requestFor([
          for (var index = 0; index < 60; index++)
            {'role': 'user', 'content': 'turn-$index'},
          {
            'role': 'assistant',
            'content': 'x' * NeuraModelRequestBudget.maxTextCharacters,
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'call-1',
                'content': 'synthetic result',
              },
            ],
          },
        ]),
      ),
      throwsA(isA<NeuraRequestBudgetExceeded>()),
    );
  });
}
