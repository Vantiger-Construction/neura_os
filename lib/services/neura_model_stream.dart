import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'neura_generation_cancel.dart';
import 'neura_model_types.dart';

sealed class NeuraStreamEvent {
  const NeuraStreamEvent(this.provider);
  final NeuraModelProvider provider;
}

class NeuraTextDelta extends NeuraStreamEvent {
  const NeuraTextDelta(super.provider, this.text);
  final String text;
}

class NeuraTurnComplete extends NeuraStreamEvent {
  const NeuraTurnComplete(super.provider, this.blocks,
      {this.openAiOutput = const []});
  final List<Map<String, dynamic>> blocks;
  // Kept only within this turn, for stateless tool continuation.
  final List<Map<String, dynamic>> openAiOutput;
}

class NeuraStreamFailure implements Exception {
  const NeuraStreamFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// One HTTP request per invocation. Routing/approval lives above this layer.
/// Never retries or executes a tool, and never logs a response body or key.
class NeuraModelStreamTransport {
  NeuraModelStreamTransport(this.provider,
      {http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  final NeuraModelProvider provider;
  final http.Client Function() _clientFactory;
  static const timeout = Duration(seconds: 30);
  static const maxStreamBytes = 2 * 1024 * 1024;

  Map<String, dynamic> buildBody(String systemPrompt,
      List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools,
      {int maxTokens = 2048}) {
    if (provider == NeuraModelProvider.openAi) {
      return {
        'model': 'gpt-5.6-luna',
        'instructions': systemPrompt,
        'input': openAiInput(messages),
        'stream': true,
        'store': false,
        'max_output_tokens': maxTokens,
        'reasoning': {'effort': 'low'},
        'include': ['reasoning.encrypted_content'],
        'parallel_tool_calls': false,
        if (tools.isNotEmpty)
          'tools': tools
              .map((tool) => {
                    'type': 'function',
                    'name': tool['name'],
                    'description': tool['description'],
                    'parameters': tool['input_schema'],
                    'strict': false,
                  })
              .toList(),
      };
    }
    return {
      'model': kNeuraAnthropicModel,
      'output_config': {'effort': kNeuraAnthropicEffort},
      'system': systemPrompt,
      'messages': messages
          .map((m) => {
                'role': m['role'],
                'content': m['content'],
              })
          .toList(),
      'max_tokens': maxTokens,
      'stream': true,
      if (tools.isNotEmpty) 'tools': tools,
    };
  }

  static List<Map<String, dynamic>> openAiInput(
      List<Map<String, dynamic>> messages) {
    final result = <Map<String, dynamic>>[];
    for (final message in messages) {
      final replay = message['openai_output'];
      if (replay is List && replay.isNotEmpty) {
        result.addAll(
            replay.map((item) => Map<String, dynamic>.from(item as Map)));
        continue;
      }
      final content = message['content'];
      if (content is String) {
        result.add({'role': message['role'], 'content': content});
        continue;
      }
      if (content is! List) {
        throw const FormatException('Invalid message content.');
      }
      final parts = <Map<String, dynamic>>[];
      for (final raw in content) {
        final block = Map<String, dynamic>.from(raw as Map);
        switch (block['type']) {
          case 'text':
            parts.add({
              'type':
                  message['role'] == 'assistant' ? 'output_text' : 'input_text',
              'text': block['text']
            });
            break;
          case 'image':
            final source = block['source'] as Map;
            if (source['type'] != 'base64') {
              throw const FormatException('Unsupported image source.');
            }
            parts.add({
              'type': 'input_image',
              'image_url':
                  'data:${source['media_type']};base64,${source['data']}'
            });
            break;
          case 'tool_result':
            result.add({
              'type': 'function_call_output',
              'call_id': block['tool_use_id'],
              'output': block['content']
            });
            break;
          default:
            throw const FormatException('Unsupported message block.');
        }
      }
      if (parts.isNotEmpty) {
        result.add({'role': message['role'], 'content': parts});
      }
    }
    return result;
  }

  Stream<NeuraStreamEvent> stream({
    required String apiKey,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required NeuraGenerationCancel cancel,
    int maxTokens = 2048,
  }) async* {
    cancel.throwIfCancelled();
    final body = buildBody(systemPrompt, messages, tools, maxTokens: maxTokens);
    final client = _clientFactory();
    final finished = Completer<void>();
    // A completed request releases its cancellation listener too.
    unawaited(Future.any([cancel.whenCancelled, finished.future]).then((_) {
      if (!finished.isCompleted) client.close();
    }));
    try {
      final openAi = provider == NeuraModelProvider.openAi;
      final request = http.Request(
          'POST',
          Uri.parse(openAi
              ? 'https://api.openai.com/v1/responses'
              : 'https://api.anthropic.com/v1/messages'))
        ..followRedirects = false
        ..headers.addAll({
          'content-type': 'application/json',
          'accept': 'text/event-stream',
          if (openAi) 'authorization': 'Bearer $apiKey',
          if (!openAi) 'x-api-key': apiKey,
          if (!openAi) 'anthropic-version': '2023-06-01',
        })
        ..body = jsonEncode(body);
      final response = await Future.any<http.StreamedResponse>([
        client.send(request).timeout(timeout),
        cancel.whenCancelled
            .then((_) => throw NeuraGenerationCancelled(cancel.generationId)),
      ]);
      cancel.throwIfCancelled();
      if (response.statusCode != 200) {
        throw NeuraStreamFailure(
            '${provider.label} request failed (${response.statusCode}).',
            statusCode: response.statusCode);
      }
      var bytes = 0;
      final bounded = response.stream.map((chunk) {
        cancel.throwIfCancelled();
        bytes += chunk.length;
        if (bytes > maxStreamBytes) {
          throw const NeuraStreamFailure('Reply exceeded the stream limit.');
        }
        return chunk;
      });
      final blocks = <int, Map<String, dynamic>>{};
      final inputs = <int, StringBuffer>{};
      final textBlocks = <int, StringBuffer>{};
      var stopReason = '';
      var sawDelta = false;
      await for (final event in _cancellableEvents(
          decodeEvents(bounded.timeout(timeout)), cancel)) {
        cancel.throwIfCancelled();
        switch (event['type']) {
          case 'response.output_text.delta':
            final text = event['delta'] as String;
            sawDelta = sawDelta || text.isNotEmpty;
            yield NeuraTextDelta(provider, text);
            break;
          case 'response.completed':
            final response = event['response'] as Map;
            if (response['status'] != 'completed') {
              throw const NeuraStreamFailure('Reply did not complete.');
            }
            final output = (response['output'] as List)
                .map((v) => Map<String, dynamic>.from(v as Map))
                .toList();
            final complete = <Map<String, dynamic>>[];
            for (final item in output) {
              if (item['type'] == 'function_call') {
                final input = jsonDecode(item['arguments'] as String);
                if (input is! Map<String, dynamic>) {
                  throw const FormatException('Invalid action arguments.');
                }
                complete.add({
                  'type': 'tool_use',
                  'id': item['call_id'],
                  'name': item['name'],
                  'input': input
                });
              } else if (item['type'] == 'message') {
                for (final part in (item['content'] as List).whereType<Map>()) {
                  if (part['type'] == 'output_text' ||
                      part['type'] == 'refusal') {
                    final text = (part['text'] ?? part['refusal']) as String;
                    complete.add({'type': 'text', 'text': text});
                    if (!sawDelta) yield NeuraTextDelta(provider, text);
                  }
                }
              }
            }
            yield NeuraTurnComplete(provider, complete, openAiOutput: output);
            return;
          case 'content_block_start':
            final index = event['index'] as int;
            blocks[index] =
                Map<String, dynamic>.from(event['content_block'] as Map);
            if (blocks[index]!['type'] == 'tool_use') {
              inputs[index] = StringBuffer();
            } else if (blocks[index]!['type'] == 'text') {
              textBlocks[index] =
                  StringBuffer(blocks[index]!['text'] as String? ?? '');
            }
            break;
          case 'content_block_delta':
            final index = event['index'] as int;
            final delta = event['delta'] as Map;
            if (delta['type'] == 'text_delta') {
              final text = delta['text'] as String;
              textBlocks[index]?.write(text);
              yield NeuraTextDelta(provider, text);
            } else if (delta['type'] == 'input_json_delta') {
              inputs[index]?.write(delta['partial_json'] as String);
            } else if (delta['type'] == 'thinking_delta') {
              // Thinking is never shown, but the block must be replayed
              // unchanged (text + signature) when a tool round continues.
              final block = blocks[index];
              if (block != null) {
                block['thinking'] =
                    '${block['thinking'] ?? ''}${delta['thinking'] ?? ''}';
              }
            } else if (delta['type'] == 'signature_delta') {
              blocks[index]?['signature'] = delta['signature'] as String;
            }
            break;
          case 'content_block_stop':
            final index = event['index'] as int;
            final raw = inputs[index]?.toString();
            if (raw != null && raw.isNotEmpty) {
              final value = jsonDecode(raw);
              if (value is! Map<String, dynamic>) {
                throw const FormatException('Invalid action arguments.');
              }
              blocks[index]?['input'] = value;
            }
            break;
          case 'message_delta':
            stopReason =
                (event['delta'] as Map)['stop_reason']?.toString() ?? '';
            break;
          case 'message_stop':
            if (!{'end_turn', 'tool_use', 'stop_sequence'}
                .contains(stopReason)) {
              throw const NeuraStreamFailure('Reply did not complete.');
            }
            for (final entry in textBlocks.entries) {
              blocks[entry.key]!['text'] = entry.value.toString();
            }
            final indices = blocks.keys.toList()..sort();
            yield NeuraTurnComplete(
                provider, indices.map((i) => blocks[i]!).toList());
            return;
          case 'error':
          case 'response.failed':
          case 'response.incomplete':
            throw const NeuraStreamFailure(
                'The provider could not complete this reply.');
        }
      }
      throw const NeuraStreamFailure(
          'Connection ended before the reply completed.');
    } on FormatException {
      cancel.throwIfCancelled();
      throw const NeuraStreamFailure(
          'The provider returned an invalid response.');
    } catch (_) {
      cancel.throwIfCancelled();
      rethrow;
    } finally {
      finished.complete();
      client.close();
    }
  }

  static Stream<Map<String, dynamic>> _cancellableEvents(
    Stream<Map<String, dynamic>> events,
    NeuraGenerationCancel cancel,
  ) async* {
    final iterator = StreamIterator(events);
    try {
      while (await Future.any<bool>([
        iterator.moveNext(),
        cancel.whenCancelled.then((_) => false),
      ])) {
        cancel.throwIfCancelled();
        yield iterator.current;
      }
      cancel.throwIfCancelled();
    } finally {
      await iterator.cancel();
    }
  }

  /// SSE framing supports fragmented UTF-8, CRLF and multiline data fields.
  static Stream<Map<String, dynamic>> decodeEvents(
      Stream<List<int>> bytes) async* {
    final data = <String>[];
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          final raw = data.join('\n');
          data.clear();
          if (raw != '[DONE]') yield jsonDecode(raw) as Map<String, dynamic>;
        }
      } else if (line.startsWith('data:')) {
        final value = line.substring(5);
        data.add(value.startsWith(' ') ? value.substring(1) : value);
      }
    }
    // An unframed final event is incomplete, never authority to run a tool.
  }
}
