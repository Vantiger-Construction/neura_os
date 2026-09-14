import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constitution/neura_constitution_service.dart';
import '../constitution/neura_personal_constitution.dart';
import '../intent_compiler/neura_action_graph.dart' show NeuraActionEffect;
import '../reliability/safe_boot.dart';
import 'neura_model_credentials.dart';
import 'neura_model_types.dart';

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
    NeuraCloudRequestPreview preview);

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
    final hasTypedImage = encoded.contains('"type":"image"');
    final hasImageUrl = encoded.contains('"image_url"');
    return NeuraCloudRequestPreview(
      provider: provider,
      purpose: purpose,
      messageCount: messages.length,
      characterCount: encoded.length,
      includesImage: hasTypedImage || hasImageUrl,
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
  NeuraOpenAiTransport({http.Client? client})
      : _client = client ?? http.Client();

  static const _endpoint = 'https://api.openai.com/v1/responses';
  static const _model = 'gpt-5.6-luna';
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
            'reasoning': {'effort': 'low'},
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
    throw NeuraModelTransportException(
      provider,
      200,
      'OpenAI returned no text.',
    );
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
    NeuraPersonalConstitution? constitution,
  })  : _credentials = credentials ?? NeuraModelCredentials.instance,
        _constitution =
            constitution ?? NeuraConstitutionService.instance.current {
    final availableTransports =
        transports ?? [NeuraOpenAiTransport(), NeuraAnthropicTransport()];
    _transports = {
      for (final transport in availableTransports)
        transport.provider: transport,
    };
  }

  final NeuraModelCredentials _credentials;
  final NeuraPersonalConstitution _constitution;
  late final Map<NeuraModelProvider, NeuraModelTransport> _transports;

  Future<NeuraModelResponse> complete(
    NeuraModelRequest request, {
    required NeuraCloudApprovalHandler requestApproval,
  }) async {
    _throwIfSafeMode();
    _throwIfConstitutionBlocks(request);
    final candidates = <NeuraModelProvider>[
      NeuraModelProvider.openAi,
      NeuraModelProvider.anthropic,
    ];

    Object? lastError;
    for (final provider in candidates) {
      _throwIfSafeMode();
      final key = await _credentials.read(provider);
      _throwIfSafeMode();
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

      late final String text;
      try {
        text = await transport.complete(apiKey: key, request: request);
      } catch (error) {
        lastError = error;
        continue;
      }
      _throwIfSafeMode();
      return NeuraModelResponse(text: text, provider: provider);
    }

    if (lastError != null) throw lastError;
    throw StateError('No securely configured model provider is available.');
  }

  void _throwIfSafeMode() {
    if (SafeBoot.instance.safeMode.value) {
      throw StateError('Cloud AI is unavailable while Neura is in Safe Mode.');
    }
  }

  /// Checked once per [complete] call, before any provider-specific approval
  /// or network call -- the decision does not depend on which provider ends
  /// up serving the request. This is the same [NeuraPersonalConstitution]
  /// Adaptive Intent and the Autonomy Kernel consult; a request a user's
  /// constitution disallows is refused before they are ever asked to
  /// approve it, not after.
  void _throwIfConstitutionBlocks(NeuraModelRequest request) {
    final decision = _constitution.evaluateEffect(
      effect: NeuraActionEffect.cloudRequest,
      at: DateTime.now(),
      safeMode: SafeBoot.instance.safeMode.value,
      containsSensitiveContent: request.includesPrivateContext,
    );
    if (!decision.allowed) {
      throw NeuraConstitutionBlocked(decision.reason);
    }
  }
}

class NeuraCloudApprovalDenied implements Exception {
  const NeuraCloudApprovalDenied();

  @override
  String toString() => 'Cloud request was not approved.';
}

/// Distinguishes a request the user's own Personal Constitution disallows
/// (never even reaches [NeuraCloudApprovalHandler]) from one a specific
/// approval prompt was declined ([NeuraCloudApprovalDenied]).
class NeuraConstitutionBlocked implements Exception {
  const NeuraConstitutionBlocked(this.reason);

  final String reason;

  @override
  String toString() =>
      'Cloud request blocked by the personal constitution: $reason';
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
