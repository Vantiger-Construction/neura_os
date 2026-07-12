import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../persona/services/neura_prompt_builder.dart';

/// One turn in the conversation, in the shape the Messages API expects.
class NeuraChatTurn {
  final bool isUser;
  final String text;
  const NeuraChatTurn({required this.isUser, required this.text});

  Map<String, dynamic> toJson() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };
}

/// Raw HTTP client for the Anthropic Messages API — there is no official
/// Dart SDK, so this talks to the streaming endpoint directly (SSE, parsed
/// by hand). See https://platform.claude.com/docs for the wire format.
///
/// The API key is baked into this beta build via --dart-define at build
/// time (ANTHROPIC_API_KEY), not committed to source control.
class NeuraAiService {
  NeuraAiService._();
  static final NeuraAiService instance = NeuraAiService._();

  static const _apiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  static const _model = 'claude-opus-4-8';
  static const _maxTokens = 1024;
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Streams incremental text deltas for a reply to [history] (last entry is
  /// the new user message). Applies Neura's persona/mood/safety system
  /// prompt (see NeuraPromptBuilder) on every call.
  Stream<String> streamReply(List<NeuraChatTurn> history) async* {
    if (!isConfigured) {
      throw StateError('ANTHROPIC_API_KEY was not set at build time.');
    }

    final systemPrompt = await NeuraPromptBuilder.instance.buildSystemMessage();

    final request = http.Request('POST', Uri.parse(_endpoint))
      ..headers.addAll({
        'content-type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      })
      ..body = jsonEncode({
        'model': _model,
        'max_tokens': _maxTokens,
        'stream': true,
        'system': systemPrompt,
        'messages': history.map((t) => t.toJson()).toList(),
      });

    final streamedResponse = await http.Client().send(request);
    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw NeuraApiException('${streamedResponse.statusCode}: $body');
    }

    var buffer = '';
    await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      // Keep the last (possibly incomplete) line in the buffer.
      buffer = lines.removeLast();

      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data.isEmpty) continue;

        final event = jsonDecode(data) as Map<String, dynamic>;
        if (event['type'] == 'content_block_delta') {
          final delta = event['delta'] as Map<String, dynamic>?;
          if (delta?['type'] == 'text_delta') {
            yield delta!['text'] as String;
          }
        } else if (event['type'] == 'error') {
          final error = event['error'] as Map<String, dynamic>?;
          throw NeuraApiException(error?['message']?.toString() ?? 'Unknown API error');
        }
      }
    }
  }
}

class NeuraApiException implements Exception {
  final String message;
  NeuraApiException(this.message);
  @override
  String toString() => message;
}
