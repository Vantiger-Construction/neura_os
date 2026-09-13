import 'dart:convert';

import 'package:http/http.dart' as http;

import '../reliability/safe_boot.dart';
import 'neura_model_credentials.dart';
import 'neura_model_types.dart';

enum NeuraModelProvider { openAi, anthropic }

extension NeuraModelProviderLabel on NeuraModelProvider {
  String get label => this == NeuraModelProvider.openAi ? 'OpenAI' : 'Anthropic';
}

class NeuraCloudRequestPreview {
  final NeuraModelProvider provider;
  final String purpose;
  final int messageCount;
  final int characterCount;
  final bool includesImage;
  final bool includesPrivateContext;

  const NeuraCloudRequestPreview({
    required this.provider,
    required this.purpose,
    required this.messageCount,
    required this.characterCount,
    required this.includesImage,
    required this.includesPrivateContext,
  });
}

typedef NeuraCloudApprovalHandler = Future<bool> Function(
  NeuraCloudRequestPreview preview,
);

class NeuraModelRequest {
  final String systemPrompt;
  final List<Map<String, dynamic>> messages;
  final String purpose;
  final bool includesPrivateContext;
  final int maxTokens;

  const NeuraModelRequest({
    required this.systemPrompt,
    required this.messages,
    required this.purpose,
    required this.includesPrivateContext,
    this.maxTokens = 2048,
  });

  NeuraCloudRequestPreview previewFor(NeuraModelProvider provider) {
    final encoded = jsonEncode(messages);
    return NeuraCloudRequestPreview(
      provider: provider,
      purpose: purpose,
      messageCount: messages.length,
      characterCount: encoded.length,
      includesImage: encoded.contains('"type":"image"') ||
          encoded.contains('"image_url"'),
      includesPrivateContext: includesPrivateContext,
    );
  }
}

class NeuraModelResponse {
  final String text;
  final NeuraModelProvider provider;

  const NeuraModelResponse({required this.text, required this.provider});
}

abstract interface class NeuraModelTransport {
  NeuraModelProvider get provider;

  Future<String> complete({
    required String apiKey,
    required NeuraModelRequest request,
  });
}

class NeuraOpenAiTransport implements NeuraModelTransport {
  NeuraOpenAiTransport({http.Client? client}) : _client = client ?? http.Client();

  static const _endpoint = 'https://api.openai.com/v1/responses';
  static const _model = 'gpt-5-mini';
  final http.Client _client;

  @override
  NeuraModelProvider get provider => NeuraModelProvider.openAi;

  @override
  Future<String> complete({
    required String apiKey,
    required NeuraModelRequest request,
  }) async {
    final input = <Map<String, dynamic>>[
      {'role': 'system', 'content': request.systemPrompt},
      ...request.messages.map(_normalizeMessage),
    ];
    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': _model,
            'input': input,
            'max_output_tokens': request.maxTokens,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw NeuraModelTransportException(
        provider,
        response.statusCode,
        'OpenAI request failed.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final direct = body['output_text'];
    if (direct is String && direct.isNotEmpty) return direct;
    final output = body['output'];
    if (output is List) {
      final parts = <String>[];
      for (final item in output.whereType<Map>()) {
        final content = item['content'];
        if (content is! List) continue;
        for (final part in content.whereType<Map>()) {
          if (part['type'] == 'output_text' && part['text'] is String) {
            parts.add(part['text'] as String);
          }
        }
      }
      if (parts.isNotEmpty) return parts.join();
    }
    throw NeuraModelTransportException(provider, 200, 'OpenAI returned no text.');
  }

  Map<String, dynamic> _normalizeMessage(Map<String, dynamic> message) {
    return {
      'role': message['role'] == 'assistant' ? 'assistant' : 'user',
      'content': message['content'],
    };
  }
}

class NeuraAnthropicTransport implements NeuraModelTransport {
  NeuraAnthropicTransport({http.Client? client})
      : _client = client ?? http.Client();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-sonnet-5';
  final http.Client _client;

  @override
  NeuraModelProvider get provider => NeuraModelProvider.anthropic;

  @override
  Future<String> complete({
    required String apiKey,
    required NeuraModelRequest request,
  }) async {
    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': _model,
            'max_tokens': request.maxTokens,
            'system': request.systemPrompt,
            'messages': request.messages,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw NeuraModelTransportException(
        provider,
        response.statusCode,
        'Anthropic request failed.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final blocks = body['content'];
    if (blocks is List) {
      final text = blocks
          .whereType<Map>()
          .where((part) => part['type'] == 'text')
          .map((part) => part['text']?.toString() ?? '')
          .join();
      if (text.isNotEmpty) return text;
    }
    throw NeuraModelTransportException(
      provider,
      200,
      'Anthropic returned no text.',
    );
  }
}

class NeuraSecureModelRouter {
  NeuraSecureModelRouter({
    NeuraModelCredentials? credentials,
    List<NeuraModelTransport>? transports,
  })  : _credentials = credentials ?? NeuraModelCredentials.instance,
        _transports = {
          for (final transport in transports ??
              [NeuraOpenAiTransport(), NeuraAnthropicTransport()])
            transport.provider: transport,
        };

  final NeuraModelCredentials _credentials;
  final Map<NeuraModelProvider, NeuraModelTransport> _transports;

  Future<NeuraModelResponse> complete(
    NeuraModelRequest request, {
    required NeuraCloudApprovalHandler requestApproval,
  }) async {
    _throwIfSafeMode();
    final candidates = <NeuraModelProvider>[
      NeuraModelProvider.openAi,
      NeuraModelProvider.anthropic,
    ];

    Object? lastError;
    for (final provider in candidates) {
      final key = await _credentials.read(provider);
      if (key == null) continue;

      // Approval is deliberately requested inside the provider loop. A
      // fallback is a second outbound request and therefore needs fresh
      // approval rather than inheriting consent from the failed primary.
      final approved = await requestApproval(request.previewFor(provider));
      _throwIfSafeMode();
      if (!approved) {
        throw const NeuraCloudApprovalDenied();
      }

      final transport = _transports[provider];
      if (transport == null) continue;
      try {
        final text = await transport.complete(apiKey: key, request: request);
        _throwIfSafeMode();
        return NeuraModelResponse(text: text, provider: provider);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) throw lastError;
    throw StateError('No securely configured model provider is available.');
  }

  void _throwIfSafeMode() {
    if (SafeBoot.instance.safeMode.value) {
      throw StateError('Cloud AI is unavailable while Neura is in Safe Mode.');
    }
  }
}

class NeuraCloudApprovalDenied implements Exception {
  const NeuraCloudApprovalDenied();

  @override
  String toString() => 'Cloud request was not approved.';
}

class NeuraModelTransportException implements Exception {
  final NeuraModelProvider provider;
  final int statusCode;
  final String message;

  const NeuraModelTransportException(
    this.provider,
    this.statusCode,
    this.message,
  );

  @override
  String toString() => '${provider.label} ($statusCode): $message';
}
