import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_companion/services/neura_cloud_transaction.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';
import 'package:neuro_companion/services/neura_model_stream.dart';
import 'package:neuro_companion/services/neura_model_types.dart';

class StreamClient extends http.BaseClient {
  StreamClient(this.events, {this.status = 200, this.headers = const {}});
  final Stream<List<int>> events;
  final int status;
  final Map<String, String> headers;
  http.BaseRequest? sent;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent = request;
    return http.StreamedResponse(events, status, headers: headers);
  }

  @override
  void close() {
    closed = true;
  }
}

List<int> frame(Map<String, dynamic> event) =>
    utf8.encode('data: ${jsonEncode(event)}\r\n\r\n');

NeuraCloudTransactionEnvelope transactionFor(NeuraModelProvider provider) =>
    NeuraCloudTransactionEnvelope(
      approvalId: 'approval-1',
      traceId: 'trace-1',
      idempotencyKey: 'idempotency-1',
      promptDigest:
          '0000000000000000000000000000000000000000000000000000000000000000',
      provider: provider,
      audience: NeuraCloudTransactionEnvelope.audienceFor(provider),
      retryCount: 0,
    );

Stream<NeuraStreamEvent> run(
  NeuraModelStreamTransport transport, {
  NeuraGenerationCancel? cancel,
}) =>
    transport.stream(
      apiKey: 'test-key',
      systemPrompt: 'Be kind.',
      messages: [
        {'role': 'user', 'content': 'Hello'},
      ],
      tools: [],
      cancel: cancel ?? NeuraGenerationCancel('test'),
      transaction: transactionFor(transport.provider),
    );

void main() {
  test('SSE decodes fragmented UTF-8 and multiline fields', () async {
    final bytes = utf8.encode(
      'event: x\r\ndata: {"type":\r\ndata: "é"}\r\n\r\n',
    );
    final events = await NeuraModelStreamTransport.decodeEvents(
      Stream.fromIterable(bytes.map((v) => [v])),
    ).toList();
    expect(events.single['type'], 'é');
  });
  test(
    'OpenAI emits text before completion and preserves function call replay',
    () async {
      final controller = StreamController<List<int>>();
      final client = StreamClient(controller.stream);
      final transport = NeuraModelStreamTransport(
        NeuraModelProvider.openAi,
        clientFactory: () => client,
      );
      final first = Completer<void>();
      final events = <NeuraStreamEvent>[];
      final subscription = run(transport).listen((event) {
        events.add(event);
        if (event is NeuraTextDelta && !first.isCompleted) first.complete();
      });
      controller.add(
        frame({'type': 'response.output_text.delta', 'delta': 'Hello.'}),
      );
      await first.future;
      expect(events.single, isA<NeuraTextDelta>());
      final output = [
        {
          'type': 'reasoning',
          'id': 'r1',
          'summary': [],
          'encrypted_content': 'opaque',
        },
        {
          'type': 'function_call',
          'call_id': 'c1',
          'name': 'set_tone',
          'arguments': '{"tone":"warm_companion"}',
        },
      ];
      controller.add(
        frame({
          'type': 'response.completed',
          'response': {'status': 'completed', 'output': output},
        }),
      );
      await subscription.asFuture<void>();
      await controller.close();
      final complete = events.last as NeuraTurnComplete;
      expect(complete.blocks.single['input'], {'tone': 'warm_companion'});
      expect(complete.openAiOutput, output);
      final body = jsonDecode((client.sent! as http.Request).body) as Map;
      expect(body['store'], false);
      expect(body['parallel_tool_calls'], false);
      expect(client.sent!.followRedirects, false);
      expect(client.sent!.headers['cache-control'], 'no-store');
      expect(client.sent!.headers['pragma'], 'no-cache');
      expect(client.sent!.headers['idempotency-key'], 'idempotency-1');
      expect(client.sent!.headers['x-neura-approval-id'], 'approval-1');
      expect(client.sent!.headers, isNot(contains('prompt-digest')));
      expect(client.closed, true);
    },
  );
  test('truncated tool stream never grants execution authority', () async {
    final client = StreamClient(
      Stream.value(
        frame({
          'type': 'response.output_item.done',
          'item': {'type': 'function_call'},
        }),
      ),
    );
    await expectLater(
      run(
        NeuraModelStreamTransport(
          NeuraModelProvider.openAi,
          clientFactory: () => client,
        ),
      ).toList(),
      throwsA(isA<NeuraStreamFailure>()),
    );
  });
  test('malformed completed tool arguments fail closed', () async {
    final client = StreamClient(
      Stream.value(
        frame({
          'type': 'response.completed',
          'response': {
            'status': 'completed',
            'output': [
              {
                'type': 'function_call',
                'call_id': 'c1',
                'name': 'set_tone',
                'arguments': '[]',
              },
            ],
          },
        }),
      ),
    );
    await expectLater(
      run(
        NeuraModelStreamTransport(
          NeuraModelProvider.openAi,
          clientFactory: () => client,
        ),
      ).toList(),
      throwsA(isA<NeuraStreamFailure>()),
    );
  });
  test('Anthropic requires message_stop after bounded tool input', () async {
    final client = StreamClient(
      Stream.fromIterable([
        frame({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'tool_use',
            'id': 'c1',
            'name': 'set_tone',
            'input': {},
          },
        }),
        frame({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': '{"tone":"warm_companion"}',
          },
        }),
        frame({'type': 'content_block_stop', 'index': 0}),
        frame({
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
        }),
        frame({'type': 'message_stop'}),
      ]),
    );
    final result = await run(
      NeuraModelStreamTransport(
        NeuraModelProvider.anthropic,
        clientFactory: () => client,
      ),
    ).toList();
    expect((result.single as NeuraTurnComplete).blocks.single['input'], {
      'tone': 'warm_companion',
    });
  });
  test(
    'Anthropic accumulates fragmented text and independent blocks exactly',
    () async {
      final deltas = List.generate(1000, (i) => '$i é 🌱 ');
      final client = StreamClient(
        Stream.fromIterable([
          frame({
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': 'Prefix '},
          }),
          for (final delta in deltas)
            frame({
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': delta},
            }),
          frame({'type': 'content_block_stop', 'index': 0}),
          frame({
            'type': 'content_block_start',
            'index': 1,
            'content_block': {'type': 'text', 'text': ''},
          }),
          frame({
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'text_delta', 'text': 'The end.'},
          }),
          frame({'type': 'content_block_stop', 'index': 1}),
          frame({
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
          }),
          frame({'type': 'message_stop'}),
        ]),
      );
      final result = await run(
        NeuraModelStreamTransport(
          NeuraModelProvider.anthropic,
          clientFactory: () => client,
        ),
      ).toList();
      expect(
        result.whereType<NeuraTextDelta>().map((e) => e.text).join(),
        '${deltas.join()}The end.',
      );
      final completed = result.last as NeuraTurnComplete;
      expect(completed.blocks, [
        {'type': 'text', 'text': 'Prefix ${deltas.join()}'},
        {'type': 'text', 'text': 'The end.'},
      ]);
      expect(client.closed, isTrue);
    },
  );

  test(
    'Anthropic keeps the signed thinking block for tool continuation',
    () async {
      final client = StreamClient(
        Stream.fromIterable([
          frame({
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'thinking', 'thinking': ''},
          }),
          frame({
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'signature_delta', 'signature': 'sig-abc'},
          }),
          frame({'type': 'content_block_stop', 'index': 0}),
          frame({
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'c1',
              'name': 'set_tone',
              'input': {},
            },
          }),
          frame({
            'type': 'content_block_delta',
            'index': 1,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': '{"tone":"x"}',
            },
          }),
          frame({'type': 'content_block_stop', 'index': 1}),
          frame({
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use'},
          }),
          frame({'type': 'message_stop'}),
        ]),
      );
      final result = await run(
        NeuraModelStreamTransport(
          NeuraModelProvider.anthropic,
          clientFactory: () => client,
        ),
      ).toList();
      final blocks = (result.last as NeuraTurnComplete).blocks;
      expect(blocks.first, {
        'type': 'thinking',
        'thinking': '',
        'signature': 'sig-abc',
      });
      expect(blocks.last['input'], {'tone': 'x'});
      expect(result.whereType<NeuraTextDelta>(), isEmpty);
    },
  );

  test(
    'buffered Anthropic text cannot complete a truncated tool stream',
    () async {
      final client = StreamClient(
        Stream.fromIterable([
          frame({
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          }),
          frame({
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Let me check.'},
          }),
          frame({'type': 'content_block_stop', 'index': 0}),
          frame({
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'unfinished',
              'name': 'set_tone',
              'input': {},
            },
          }),
        ]),
      );
      final seen = <NeuraStreamEvent>[];
      await expectLater(
        run(
          NeuraModelStreamTransport(
            NeuraModelProvider.anthropic,
            clientFactory: () => client,
          ),
        ).map((event) {
          seen.add(event);
          return event;
        }).toList(),
        throwsA(isA<NeuraStreamFailure>()),
      );
      expect((seen.single as NeuraTextDelta).text, 'Let me check.');
      expect(seen.whereType<NeuraTurnComplete>(), isEmpty);
    },
  );

  test('image and tool results use Responses input shapes', () {
    final input = NeuraModelStreamTransport.openAiInput([
      {
        'role': 'user',
        'content': [
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': 'image/png',
              'data': 'aGVsbG8=',
            },
          },
          {'type': 'text', 'text': 'Explain'},
        ],
      },
      {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': 'c1', 'content': 'Denied'},
        ],
      },
    ]);
    expect((input.first['content'] as List).first['type'], 'input_image');
    expect(input.last, {
      'type': 'function_call_output',
      'call_id': 'c1',
      'output': 'Denied',
    });
  });
  test('HTTP errors never reveal provider body', () async {
    final client = StreamClient(
      Stream.value(utf8.encode('secret journal text')),
      status: 429,
    );
    await expectLater(
      run(
        NeuraModelStreamTransport(
          NeuraModelProvider.openAi,
          clientFactory: () => client,
        ),
      ).toList(),
      throwsA(
        isA<NeuraStreamFailure>().having(
          (e) => e.toString(),
          'message',
          isNot(contains('secret')),
        ),
      ),
    );
  });
  test(
    'HTTP rate limits expose typed retry policy without provider body',
    () async {
      final client = StreamClient(
        Stream.value(utf8.encode('private provider details')),
        status: 429,
        headers: const {'retry-after': '3'},
      );
      try {
        await run(
          NeuraModelStreamTransport(
            NeuraModelProvider.openAi,
            clientFactory: () => client,
          ),
        ).toList();
        fail('Expected a typed stream failure.');
      } on NeuraStreamFailure catch (failure) {
        expect(failure.kind, NeuraModelFailureKind.rateLimited);
        expect(failure.retryable, isTrue);
        expect(failure.retryAfter, const Duration(seconds: 3));
        expect(failure.toString(), isNot(contains('private')));
      }
    },
  );
  test('authentication failures are never retried', () {
    expect(
      neuraFailureKindForStatus(401),
      NeuraModelFailureKind.authentication,
    );
    expect(neuraFailureKindForStatus(401).retryable, isFalse);
    expect(neuraFailureKindForStatus(503).retryable, isTrue);
  });
  test('pre-cancelled generation sends nothing', () async {
    final cancel = NeuraGenerationCancel('cancelled')..cancel();
    var clients = 0;
    final transport = NeuraModelStreamTransport(
      NeuraModelProvider.openAi,
      clientFactory: () {
        clients++;
        return StreamClient(const Stream.empty());
      },
    );
    await expectLater(
      run(transport, cancel: cancel).toList(),
      throwsA(isA<NeuraGenerationCancelled>()),
    );
    expect(clients, 0);
  });
}
