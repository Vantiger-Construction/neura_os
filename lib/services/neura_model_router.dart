import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../constitution/neura_constitution_service.dart';
import '../constitution/neura_personal_constitution.dart';
import '../intent_compiler/neura_action_graph.dart' show NeuraActionEffect;
import '../reliability/safe_boot.dart';
import 'neura_model_credentials.dart';
import 'neura_cloud_transaction.dart';
import 'neura_generation_cancel.dart';
import 'neura_llm_diagnostics.dart';
import 'neura_model_stream.dart';
import 'neura_model_types.dart';

class NeuraCloudRequestPreview {
  final NeuraModelProvider provider;
  final NeuraCloudTransactionEnvelope transaction;
  final String purpose;
  final int messageCount;
  final int characterCount;
  final int omittedMessageCount;
  final bool includesImage;
  final bool includesPrivateContext;
  final String textPreview;

  const NeuraCloudRequestPreview({
    required this.provider,
    required this.transaction,
    required this.purpose,
    required this.messageCount,
    required this.characterCount,
    this.omittedMessageCount = 0,
    required this.includesImage,
    required this.includesPrivateContext,
    this.textPreview = '',
  });

  NeuraCloudApprovalState get approvalState => transaction.approvalState;
  String get approvalId => transaction.approvalId;
  String get traceId => transaction.traceId;
  String get promptDigest => transaction.promptDigest;
  Uri get audience => transaction.audience;
  int get retryCount => transaction.retryCount;
  bool get privateCacheProhibited => transaction.privateCacheProhibited;
}

typedef NeuraCloudApprovalHandler = Future<bool> Function(
    NeuraCloudRequestPreview preview);

class NeuraModelRequest {
  final String systemPrompt;
  final List<Map<String, dynamic>> messages;
  final String purpose;
  final bool includesPrivateContext;
  final int maxTokens;
  final int omittedMessageCount;
  final NeuraCloudTransactionEnvelope? transaction;

  const NeuraModelRequest({
    required this.systemPrompt,
    required this.messages,
    required this.purpose,
    required this.includesPrivateContext,
    this.maxTokens = 2048,
    this.omittedMessageCount = 0,
    this.transaction,
  });

  NeuraCloudRequestPreview previewFor(
    NeuraModelProvider provider,
    NeuraCloudTransactionEnvelope transaction,
  ) {
    final encoded = jsonEncode(messages);
    final hasTypedImage = encoded.contains('"type":"image"');
    final hasImageUrl = encoded.contains('"image_url"');
    return NeuraCloudRequestPreview(
      provider: provider,
      transaction: transaction,
      purpose: purpose,
      messageCount: messages.length,
      characterCount: encoded.length + systemPrompt.length,
      omittedMessageCount: omittedMessageCount,
      includesImage: hasTypedImage || hasImageUrl,
      includesPrivateContext: includesPrivateContext,
      textPreview: _previewText(systemPrompt, messages),
    );
  }

  NeuraModelRequest bindTransaction(
    NeuraCloudTransactionEnvelope envelope,
  ) {
    return NeuraModelRequest(
      systemPrompt: systemPrompt,
      messages: messages,
      purpose: purpose,
      includesPrivateContext: includesPrivateContext,
      maxTokens: maxTokens,
      omittedMessageCount: omittedMessageCount,
      transaction: envelope,
    );
  }
}

/// Enforces a predictable request envelope before the approval preview is
/// shown. Recent messages win; the latest user/tool exchange is never silently
/// dropped. Image bytes count toward the wire budget but not the text budget.
class NeuraModelRequestBudget {
  static const maxMessages = 48;
  static const maxTextCharacters = 96 * 1024;
  static const maxWireCharacters = 8 * 1024 * 1024;
  static const maxSystemCharacters = 32 * 1024;
  static const maxToolCharacters = 64 * 1024;
  static const maxTools = 32;

  static NeuraModelRequest freezeAndApply(NeuraModelRequest source) {
    if (source.systemPrompt.length > maxSystemCharacters) {
      throw const NeuraRequestBudgetExceeded(
        'The system instructions exceed the safe request budget.',
      );
    }
    final messages = (jsonDecode(jsonEncode(source.messages)) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    if (messages.isEmpty) {
      return NeuraModelRequest(
        systemPrompt: source.systemPrompt,
        messages: const [],
        purpose: source.purpose,
        includesPrivateContext: source.includesPrivateContext,
        maxTokens: source.maxTokens,
        omittedMessageCount: source.omittedMessageCount,
        transaction: source.transaction,
      );
    }

    var mandatoryStart = messages.length - 1;
    if (_containsType(messages.last, 'tool_result') && messages.length > 1) {
      mandatoryStart--;
    }
    final kept = messages.sublist(mandatoryStart).toList();
    var textCharacters = source.systemPrompt.length + _textSize(kept);
    var wireCharacters = source.systemPrompt.length + jsonEncode(kept).length;
    if (textCharacters > maxTextCharacters ||
        wireCharacters > maxWireCharacters ||
        kept.length > maxMessages) {
      throw const NeuraRequestBudgetExceeded(
        'The latest message or action result is too large to send safely.',
      );
    }

    for (var index = mandatoryStart - 1; index >= 0; index--) {
      final candidate = messages[index];
      final nextText = textCharacters + _textSize(candidate);
      final nextWire = wireCharacters + jsonEncode(candidate).length;
      if (kept.length >= maxMessages ||
          nextText > maxTextCharacters ||
          nextWire > maxWireCharacters) {
        break;
      }
      kept.insert(0, candidate);
      textCharacters = nextText;
      wireCharacters = nextWire;
    }

    return NeuraModelRequest(
      systemPrompt: source.systemPrompt,
      messages: List.unmodifiable(kept),
      purpose: source.purpose,
      includesPrivateContext: source.includesPrivateContext,
      maxTokens: source.maxTokens,
      omittedMessageCount:
          source.omittedMessageCount + messages.length - kept.length,
      transaction: source.transaction,
    );
  }

  static List<Map<String, dynamic>> freezeTools(
      List<Map<String, dynamic>> tools) {
    final frozen = (jsonDecode(jsonEncode(tools)) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    if (frozen.length > maxTools ||
        jsonEncode(frozen).length > maxToolCharacters) {
      throw const NeuraRequestBudgetExceeded(
        'The action definitions exceed the safe request budget.',
      );
    }
    return List.unmodifiable(frozen);
  }

  static bool _containsType(Object? value, String type) {
    if (value is Map) {
      if (value['type'] == type) return true;
      return value.values.any((item) => _containsType(item, type));
    }
    if (value is List) {
      return value.any((item) => _containsType(item, type));
    }
    return false;
  }

  static int _textSize(Object? value, {String? key}) {
    if (value is String) return key == 'data' ? 0 : value.length;
    if (value is List) {
      return value.fold(0, (sum, item) => sum + _textSize(item));
    }
    if (value is Map) {
      var total = 0;
      for (final entry in value.entries) {
        total += entry.key.toString().length;
        total += _textSize(entry.value, key: entry.key.toString());
      }
      return total;
    }
    return value?.toString().length ?? 0;
  }
}

class NeuraRequestBudgetExceeded implements Exception {
  const NeuraRequestBudgetExceeded(this.message);
  final String message;

  @override
  String toString() => message;
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
    final transaction = request.transaction;
    if (transaction == null) {
      throw StateError('Cloud transaction metadata is required.');
    }
    final endpoint = Uri.parse(_endpoint);
    transaction.validateFor(
      requestedProvider: provider,
      requestedAudience: endpoint,
    );
    final input = <Map<String, dynamic>>[
      {'role': 'system', 'content': request.systemPrompt},
      ...request.messages.map(_normalizeMessage),
    ];
    final response = await _client
        .post(
          endpoint,
          headers: {
            'authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
            ...transaction.requestHeaders(),
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
        kind: neuraFailureKindForStatus(response.statusCode),
        retryAfter: neuraRetryAfter(response.headers['retry-after']),
      );
    }
    if (response.bodyBytes.length > NeuraModelStreamTransport.maxStreamBytes) {
      throw NeuraModelTransportException(
        provider,
        200,
        'OpenAI returned an oversized response.',
        kind: NeuraModelFailureKind.invalidResponse,
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
      kind: NeuraModelFailureKind.invalidResponse,
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
    final transaction = request.transaction;
    if (transaction == null) {
      throw StateError('Cloud transaction metadata is required.');
    }
    final endpoint = Uri.parse(_endpoint);
    transaction.validateFor(
      requestedProvider: provider,
      requestedAudience: endpoint,
    );
    final response = await _client
        .post(
          endpoint,
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
            ...transaction.requestHeaders(),
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
        kind: neuraFailureKindForStatus(response.statusCode),
        retryAfter: neuraRetryAfter(response.headers['retry-after']),
      );
    }
    if (response.bodyBytes.length > NeuraModelStreamTransport.maxStreamBytes) {
      throw NeuraModelTransportException(
        provider,
        200,
        'Anthropic returned an oversized response.',
        kind: NeuraModelFailureKind.invalidResponse,
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
      kind: NeuraModelFailureKind.invalidResponse,
    );
  }
}

class NeuraSecureModelRouter {
  NeuraSecureModelRouter({
    NeuraModelCredentials? credentials,
    List<NeuraModelTransport>? transports,
    NeuraPersonalConstitution? constitution,
    List<NeuraModelStreamTransport>? streamTransports,
    DateTime Function()? now,
    Future<void> Function(Duration, NeuraGenerationCancel?)? sleep,
    Random? random,
    NeuraLlmDiagnostics? diagnostics,
    NeuraCloudTransactionFactory? transactionFactory,
    NeuraCloudAuditTrail? auditTrail,
  })  : _credentials = credentials ?? NeuraModelCredentials.instance,
        _constitutionOverride = constitution,
        _now = now ?? DateTime.now,
        _sleep = sleep ?? _defaultSleep,
        _random = random ?? Random(),
        _diagnostics = diagnostics ?? NeuraLlmDiagnostics.instance,
        _transactionFactory =
            transactionFactory ?? NeuraCloudTransactionFactory(),
        _auditTrail = auditTrail ?? NeuraCloudAuditTrail() {
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
  final DateTime Function() _now;
  final Future<void> Function(Duration, NeuraGenerationCancel?) _sleep;
  final Random _random;
  final NeuraLlmDiagnostics _diagnostics;
  final NeuraCloudTransactionFactory _transactionFactory;
  final NeuraCloudAuditTrail _auditTrail;
  final Map<NeuraModelProvider, _NeuraProviderCircuit> _circuits = {
    for (final provider in NeuraModelProvider.values)
      provider: _NeuraProviderCircuit(),
  };
  late final Map<NeuraModelProvider, NeuraModelTransport> _transports;

  late final Map<NeuraModelProvider, NeuraModelStreamTransport>
      _streamTransports;

  Map<String, Object?> get providerHealthSnapshot => {
        for (final entry in _circuits.entries)
          entry.key.name: entry.value.snapshot(_now()),
      };

  List<Map<String, Object?>> get cloudAuditSnapshot => _auditTrail.events
      .map((event) => event.toJson())
      .toList(growable: false);

  Stream<NeuraStreamEvent> stream(
    NeuraModelRequest request, {
    required List<Map<String, dynamic>> tools,
    required NeuraGenerationCancel cancel,
    required NeuraCloudApprovalHandler requestApproval,
    NeuraModelProvider? provider,
  }) async* {
    // Freeze and bound the exact body before its approval preview is shown.
    final previouslyOmitted = request.omittedMessageCount;
    request = NeuraModelRequestBudget.freezeAndApply(request);
    _diagnostics.recordContextOmission(
      request.omittedMessageCount - previouslyOmitted,
    );
    final frozenTools = NeuraModelRequestBudget.freezeTools(tools);
    final traceId = _transactionFactory.newTraceId();
    final canonicalPayload = _canonicalPayload(request, frozenTools);
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
      var switchingProvider = false;
      for (final candidate
          in provider == null ? NeuraModelProvider.values : [provider]) {
        check();
        final transport = _streamTransports[candidate];
        if (transport == null) continue;
        final circuit = _circuits[candidate]!;
        if (provider == null && circuit.isOpen(_now())) {
          lastError = NeuraProviderCircuitOpen(candidate, circuit.openUntil!);
          switchingProvider = true;
          continue;
        }
        final key = await _credentials.read(candidate);
        check();
        if (key == null) continue;
        if (switchingProvider) {
          _diagnostics.recordProviderFallback();
          switchingProvider = false;
        }
        final idempotencyKey = _transactionFactory.newIdempotencyKey();
        var failed = false;
        for (var attempt = 0; attempt < 2; attempt++) {
          final transaction = await _transactionFactory.create(
            provider: candidate,
            canonicalPayload: canonicalPayload,
            traceId: traceId,
            idempotencyKey: idempotencyKey,
            retryCount: attempt,
          );
          check();
          _auditTrail.record(
            transaction,
            NeuraCloudAuditStage.approvalRequired,
          );
          final approved = await Future.any<bool>([
            requestApproval(request.previewFor(candidate, transaction)),
            cancel.whenCancelled.then((_) => false),
          ]);
          check();
          if (!approved) {
            _auditTrail.record(transaction, NeuraCloudAuditStage.denied);
            throw const NeuraCloudApprovalDenied();
          }
          _auditTrail.record(transaction, NeuraCloudAuditStage.approved);
          var emitted = false;
          try {
            _auditTrail.record(transaction, NeuraCloudAuditStage.sent);
            await for (final event in transport.stream(
              apiKey: key,
              systemPrompt: request.systemPrompt,
              messages: request.messages,
              tools: frozenTools,
              cancel: cancel,
              maxTokens: request.maxTokens,
              transaction: transaction,
            )) {
              check();
              emitted = true;
              yield event;
            }
            circuit.recordSuccess();
            _auditTrail.record(transaction, NeuraCloudAuditStage.succeeded);
            return;
          } catch (error) {
            check();
            final failure = _streamFailure(error);
            _auditTrail.record(
              transaction,
              NeuraCloudAuditStage.failed,
              failureKind: failure.kind.name,
            );
            circuit.recordFailure(failure.kind, _now());
            lastError = failure;
            failed = true;
            // A continuation follows tool execution and must never replay.
            // Visible output also makes any retry or provider switch unsafe.
            if (emitted || provider != null) rethrow;
            final retry = attempt == 0 && failure.retryable;
            if (!retry) break;
            _diagnostics.recordRetry();
            await _sleep(_retryDelay(failure), cancel);
            check();
            // The loop obtains a new visible approval before retrying.
          }
        }
        if (failed && provider == null) switchingProvider = true;
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
    final previouslyOmitted = request.omittedMessageCount;
    request = NeuraModelRequestBudget.freezeAndApply(request);
    _diagnostics.recordContextOmission(
      request.omittedMessageCount - previouslyOmitted,
    );
    _throwIfSafeMode();
    if (_constitutionOverride == null) {
      await NeuraConstitutionService.instance.load();
    }
    _throwIfSafeMode();
    _throwIfConstitutionBlocks(request);
    final traceId = _transactionFactory.newTraceId();
    final canonicalPayload = _canonicalPayload(request, const []);
    final candidates = <NeuraModelProvider>[
      NeuraModelProvider.openAi,
      NeuraModelProvider.anthropic,
    ];

    Object? lastError;
    var switchingProvider = false;
    for (final provider in candidates) {
      _throwIfSafeMode();
      _throwIfConstitutionBlocks(request);
      final circuit = _circuits[provider]!;
      if (circuit.isOpen(_now())) {
        lastError = NeuraProviderCircuitOpen(provider, circuit.openUntil!);
        switchingProvider = true;
        continue;
      }
      final key = await _credentials.read(provider);
      _throwIfSafeMode();
      _throwIfConstitutionBlocks(request);
      if (key == null) continue;
      if (switchingProvider) {
        _diagnostics.recordProviderFallback();
        switchingProvider = false;
      }

      final transport = _transports[provider];
      if (transport == null) continue;

      final idempotencyKey = _transactionFactory.newIdempotencyKey();
      var failed = false;
      for (var attempt = 0; attempt < 2; attempt++) {
        // Every outbound attempt, including an exact retry or fallback,
        // receives a new preview and a new decision.
        final transaction = await _transactionFactory.create(
          provider: provider,
          canonicalPayload: canonicalPayload,
          traceId: traceId,
          idempotencyKey: idempotencyKey,
          retryCount: attempt,
        );
        _throwIfSafeMode();
        _throwIfConstitutionBlocks(request);
        _auditTrail.record(
          transaction,
          NeuraCloudAuditStage.approvalRequired,
        );
        final approved = await requestApproval(
          request.previewFor(provider, transaction),
        );
        _throwIfSafeMode();
        if (!approved) {
          _auditTrail.record(transaction, NeuraCloudAuditStage.denied);
          throw const NeuraCloudApprovalDenied();
        }
        _auditTrail.record(transaction, NeuraCloudAuditStage.approved);
        _throwIfConstitutionBlocks(request);

        try {
          _auditTrail.record(transaction, NeuraCloudAuditStage.sent);
          final text = await transport.complete(
            apiKey: key,
            request: request.bindTransaction(transaction),
          );
          _throwIfSafeMode();
          circuit.recordSuccess();
          _auditTrail.record(transaction, NeuraCloudAuditStage.succeeded);
          return NeuraModelResponse(text: text, provider: provider);
        } catch (error) {
          _throwIfSafeMode();
          _throwIfConstitutionBlocks(request);
          final failure = _completionFailure(provider, error);
          _auditTrail.record(
            transaction,
            NeuraCloudAuditStage.failed,
            failureKind: failure.kind.name,
          );
          circuit.recordFailure(failure.kind, _now());
          lastError = failure;
          failed = true;
          if (attempt != 0 || !failure.retryable) break;
          _diagnostics.recordRetry();
          await _sleep(_retryDelay(failure), null);
          _throwIfSafeMode();
          _throwIfConstitutionBlocks(request);
        }
      }
      if (failed) switchingProvider = true;
    }

    if (lastError != null) throw lastError;
    throw StateError('No securely configured model provider is available.');
  }

  Duration _retryDelay(Object failure) {
    final supplied = switch (failure) {
      NeuraStreamFailure value => value.retryAfter,
      NeuraModelTransportException value => value.retryAfter,
      _ => null,
    };
    if (supplied != null) {
      return supplied > const Duration(seconds: 30)
          ? const Duration(seconds: 30)
          : supplied;
    }
    return Duration(milliseconds: 250 + _random.nextInt(251));
  }

  String _canonicalPayload(
    NeuraModelRequest request,
    List<Map<String, dynamic>> tools,
  ) {
    return jsonEncode({
      'system_prompt': request.systemPrompt,
      'messages': request.messages,
      'tools': tools,
      'purpose': request.purpose,
      'includes_private_context': request.includesPrivateContext,
      'max_tokens': request.maxTokens,
    });
  }

  NeuraStreamFailure _streamFailure(Object error) {
    if (error is NeuraStreamFailure) return error;
    if (error is TimeoutException) {
      return const NeuraStreamFailure(
        'The model request timed out.',
        kind: NeuraModelFailureKind.timeout,
      );
    }
    if (error is http.ClientException) {
      return const NeuraStreamFailure(
        'The model connection failed.',
        kind: NeuraModelFailureKind.connection,
      );
    }
    return const NeuraStreamFailure(
      'The model provider failed.',
      kind: NeuraModelFailureKind.unknown,
    );
  }

  NeuraModelTransportException _completionFailure(
      NeuraModelProvider provider, Object error) {
    if (error is NeuraModelTransportException) return error;
    if (error is TimeoutException) {
      return NeuraModelTransportException(
        provider,
        408,
        'The model request timed out.',
        kind: NeuraModelFailureKind.timeout,
      );
    }
    if (error is http.ClientException) {
      return NeuraModelTransportException(
        provider,
        0,
        'The model connection failed.',
        kind: NeuraModelFailureKind.connection,
      );
    }
    return NeuraModelTransportException(
      provider,
      0,
      'The model provider failed.',
      kind: error is FormatException
          ? NeuraModelFailureKind.invalidResponse
          : NeuraModelFailureKind.unknown,
    );
  }

  static Future<void> _defaultSleep(
      Duration duration, NeuraGenerationCancel? cancel) async {
    if (cancel != null) {
      await cancel.delay(duration);
    } else {
      await Future<void>.delayed(duration);
    }
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
  final NeuraModelFailureKind kind;
  final Duration? retryAfter;
  bool get retryable => kind.retryable;

  const NeuraModelTransportException(
    this.provider,
    this.statusCode,
    this.message, {
    this.kind = NeuraModelFailureKind.unknown,
    this.retryAfter,
  });

  @override
  String toString() => '${provider.label} ($statusCode): $message';
}

class NeuraProviderCircuitOpen implements Exception {
  const NeuraProviderCircuitOpen(this.provider, this.retryAt);
  final NeuraModelProvider provider;
  final DateTime retryAt;

  @override
  String toString() => '${provider.label} is temporarily unavailable.';
}

class _NeuraProviderCircuit {
  static const failureThreshold = 3;
  static const openDuration = Duration(seconds: 30);

  int consecutiveTransientFailures = 0;
  DateTime? openUntil;

  bool isOpen(DateTime now) {
    final until = openUntil;
    if (until == null) return false;
    if (now.isBefore(until)) return true;
    openUntil = null;
    consecutiveTransientFailures = 0;
    return false;
  }

  void recordFailure(NeuraModelFailureKind kind, DateTime now) {
    if (!kind.retryable) return;
    consecutiveTransientFailures++;
    if (consecutiveTransientFailures >= failureThreshold) {
      openUntil = now.add(openDuration);
    }
  }

  void recordSuccess() {
    consecutiveTransientFailures = 0;
    openUntil = null;
  }

  Map<String, Object?> snapshot(DateTime now) => {
        'state': isOpen(now) ? 'open' : 'closed',
        'consecutive_transient_failures': consecutiveTransientFailures,
        'retry_at': openUntil?.toUtc().toIso8601String(),
      };
}
