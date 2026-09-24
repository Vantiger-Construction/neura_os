import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constitution/neura_constitution_service.dart';
import '../constitution/neura_personal_constitution.dart';
import '../intent_compiler/neura_action_graph.dart' show NeuraActionEffect;
import '../reliability/safe_boot.dart';
import 'neura_model_credentials.dart';
import 'neura_generation_cancel.dart';
import 'neura_model_stream.dart';
import 'neura_model_types.dart';

class NeuraCloudRequestPreview {
  final NeuraModelProvider provider;
  final String purpose;
  final int messageCount;
  final int characterCount;
  final bool includesImage;
  final bool includesPrivateContext;
  final String textPreview;

  const NeuraCloudRequestPreview({
    required this.provider,
    required this.purpose,
    required this.messageCount,
    required this.characterCount,
    required this.includesImage,
    required this.includesPrivateContext,
    this.textPreview = '',
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
      characterCount: encoded.length + systemPrompt.length,
      includesImage: hasTypedImage || hasImageUrl,
      includesPrivateContext: includesPrivateContext,
      textPreview: _previewText(systemPrompt, messages),
    );
  }
}

String _previewText(String systemPrompt, List<Map<String, dynamic>> messages) {
  final lines = <String>['Instructions and permitted context:', systemPrompt];
  for (final message in messages) {
    lines.add('${message['role']}:');
    final content = message['content'];
    if (content is String) {
      lines.add(content);
    } else if (content is List) {
      for (final block in content.whereType<Map>()) {
        lines.add(block['type'] == 'image'
            ? '[Attached image]'
            : (block['text'] ?? block['content'] ?? '[Action request]')
                .toString());
      }
    }
  }
  return lines.join('\n');
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
            'store': false,
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
            'model': kNeuraAnthropicModel,
            'max_tokens': request.maxTokens,
            'system': request.systemPrompt,
            'messages': request.messages,
            'output_config': {'effort': kNeuraAnthropicEffort},
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
    List<NeuraModelStreamTransport>? streamTransports,
  })  : _credentials = credentials ?? NeuraModelCredentials.instance,
        _constitutionOverride = constitution {
    final availableTransports =
        transports ?? [NeuraOpenAiTransport(), NeuraAnthropicTransport()];
    _streamTransports = {
      for (final transport in streamTransports ??
          NeuraModelProvider.values.map(NeuraModelStreamTransport.new))
        transport.provider: transport,
    };
    _transports = {
      for (final transport in availableTransports)
        transport.provider: transport,
    };
  }

  final NeuraModelCredentials _credentials;
  final NeuraPersonalConstitution? _constitutionOverride;
  late final Map<NeuraModelProvider, NeuraModelTransport> _transports;

  late final Map<NeuraModelProvider, NeuraModelStreamTransport>
      _streamTransports;

  Stream<NeuraStreamEvent> stream(
    NeuraModelRequest request, {
    required List<Map<String, dynamic>> tools,
    required NeuraGenerationCancel cancel,
    required NeuraCloudApprovalHandler requestApproval,
    NeuraModelProvider? provider,
  }) async* {
    // Freeze the request before preview: callers cannot change the approved body.
    request = NeuraModelRequest(
      systemPrompt: request.systemPrompt,
      messages: (jsonDecode(jsonEncode(request.messages)) as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      purpose: request.purpose,
      includesPrivateContext: request.includesPrivateContext,
      maxTokens: request.maxTokens,
    );
    final frozenTools = (jsonDecode(jsonEncode(tools)) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    void check() {
      cancel.throwIfCancelled();
      _throwIfSafeMode();
      _throwIfConstitutionBlocks(request);
    }

    void onSafeMode() {
      if (SafeBoot.instance.safeMode.value) cancel.cancel();
    }

    SafeBoot.instance.safeMode.addListener(onSafeMode);
    try {
      _throwIfSafeMode();
      if (_constitutionOverride == null) {
        await NeuraConstitutionService.instance.load();
      }
      check();
      Object? lastError;
      for (final candidate
          in provider == null ? NeuraModelProvider.values : [provider]) {
        check();
        final transport = _streamTransports[candidate];
        if (transport == null) continue;
        final key = await _credentials.read(candidate);
        check();
        if (key == null) continue;
        final approved = await Future.any<bool>([
          requestApproval(request.previewFor(candidate)),
          cancel.whenCancelled.then((_) => false),
        ]);
        check();
        if (!approved) throw const NeuraCloudApprovalDenied();
        var emitted = false;
        try {
          await for (final event in transport.stream(
            apiKey: key,
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            tools: frozenTools,
            cancel: cancel,
            maxTokens: request.maxTokens,
          )) {
            check();
            emitted = true;
            yield event;
          }
          return;
        } catch (error) {
          check();
          // Never replay a partial answer or a tool round through another provider.
          if (emitted ||
              provider != null ||
              !(error is NeuraStreamFailure ||
                  error is http.ClientException ||
                  error is TimeoutException)) {
            rethrow;
          }
          lastError = error;
        }
      }
      throw lastError ??
          StateError('No securely configured model provider is available.');
    } finally {
      SafeBoot.instance.safeMode.removeListener(onSafeMode);
    }
  }

  Future<NeuraModelResponse> complete(
    NeuraModelRequest request, {
    required NeuraCloudApprovalHandler requestApproval,
  }) async {
    request = NeuraModelRequest(
      systemPrompt: request.systemPrompt,
      messages: (jsonDecode(jsonEncode(request.messages)) as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      purpose: request.purpose,
      includesPrivateContext: request.includesPrivateContext,
      maxTokens: request.maxTokens,
    );
    _throwIfSafeMode();
    if (_constitutionOverride == null) {
      await NeuraConstitutionService.instance.load();
    }
    _throwIfSafeMode();
    _throwIfConstitutionBlocks(request);
    final candidates = <NeuraModelProvider>[
      NeuraModelProvider.openAi,
      NeuraModelProvider.anthropic,
    ];

    Object? lastError;
    for (final provider in candidates) {
      _throwIfSafeMode();
      _throwIfConstitutionBlocks(request);
      final key = await _credentials.read(provider);
      _throwIfSafeMode();
      _throwIfConstitutionBlocks(request);
      if (key == null) continue;

      // Approval is deliberately requested inside the provider loop. A
      // fallback is a second outbound request and therefore needs fresh
      // approval rather than inheriting consent from the failed primary.
      final approved = await requestApproval(request.previewFor(provider));
      _throwIfSafeMode();
      if (!approved) {
        throw const NeuraCloudApprovalDenied();
      }
      _throwIfConstitutionBlocks(request);

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

  /// Checked before approval and again immediately before each outbound
  /// request. A production router reads the service's current value rather
  /// than freezing a pre-load snapshot; an explicit test override stays
  /// isolated from global state.
  void _throwIfConstitutionBlocks(NeuraModelRequest request) {
    final constitution =
        _constitutionOverride ?? NeuraConstitutionService.instance.current;
    final decision = constitution.evaluateEffect(
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
