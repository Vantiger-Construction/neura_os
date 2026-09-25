import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/constitution/neura_constitution_service.dart';
import 'package:neuro_companion/constitution/neura_personal_constitution.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_cloud_transaction.dart';
import 'package:neuro_companion/services/neura_model_credentials.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_model_types.dart';
import 'package:neuro_companion/services/neura_model_stream.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

class _MemoryStorage implements NeuraModelCredentialStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

NeuraCloudTransactionEnvelope _transactionFor(
  NeuraModelProvider provider,
) =>
    NeuraCloudTransactionEnvelope(
      approvalId: 'approval-test',
      traceId: 'trace-test',
      idempotencyKey: 'idempotency-test',
      promptDigest:
          '0000000000000000000000000000000000000000000000000000000000000000',
      provider: provider,
      audience: NeuraCloudTransactionEnvelope.audienceFor(provider),
      retryCount: 0,
    );

class _Transport implements NeuraModelTransport {
  _Transport(this.provider, {this.result, this.error, this.onComplete});

  @override
  final NeuraModelProvider provider;
  final String? result;
  final Object? error;
  final void Function()? onComplete;
  int calls = 0;
  final List<NeuraCloudTransactionEnvelope> transactions = [];

  @override
  Future<String> complete({
    required String apiKey,
    required NeuraModelRequest request,
  }) async {
    calls++;
    final transaction = request.transaction;
    if (transaction != null) transactions.add(transaction);
    onComplete?.call();
    if (error != null) throw error!;
    return result!;
  }
}

class _StreamTransport extends NeuraModelStreamTransport {
  _StreamTransport(super.provider, this.events);
  final Stream<NeuraStreamEvent> Function() events;
  int calls = 0;
  final List<NeuraCloudTransactionEnvelope> transactions = [];
  @override
  Stream<NeuraStreamEvent> stream({
    required String apiKey,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required NeuraGenerationCancel cancel,
    required NeuraCloudTransactionEnvelope transaction,
    int maxTokens = 2048,
  }) {
    calls++;
    transactions.add(transaction);
    return events();
  }
}

class _SequenceTransport implements NeuraModelTransport {
  _SequenceTransport(this.provider, this.outcomes);

  @override
  final NeuraModelProvider provider;
  final List<Object> outcomes;
  int calls = 0;

  @override
  Future<String> complete({
    required String apiKey,
    required NeuraModelRequest request,
  }) async {
    final outcome = outcomes[calls++];
    if (outcome is String) return outcome;
    throw outcome;
  }
}

void main() {
  const openAiKey = 'sk-openai-test-key-1234567890';
  const anthropicKey = 'sk-ant-test-key-1234567890';
  const request = NeuraModelRequest(
    systemPrompt: 'Be kind.',
    messages: [
      {'role': 'user', 'content': 'Hello'},
    ],
    purpose: 'chat reply',
    includesPrivateContext: false,
  );

  late bool originalSafeMode;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    originalSafeMode = SafeBoot.instance.safeMode.value;
    SafeBoot.instance.safeMode.value = false;
    await NeuraPrefsCache.prefs.remove('neura.constitution.v1');
    await NeuraPrefsCache.prefs.remove('neura.adaptive_intent.state.v1');
    NeuraConstitutionService.instance.resetAfterDataWipe();
  });

  tearDown(() {
    SafeBoot.instance.safeMode.value = originalSafeMode;
    NeuraConstitutionService.instance.resetAfterDataWipe();
  });

  test('stream fallback needs fresh approval and denial sends nothing',
      () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    await credentials.save(NeuraModelProvider.anthropic, anthropicKey);
    final primary = _StreamTransport(NeuraModelProvider.openAi,
        () => Stream.error(const NeuraStreamFailure('unavailable')));
    final fallback = _StreamTransport(
        NeuraModelProvider.anthropic,
        () => Stream.value(
            const NeuraTextDelta(NeuraModelProvider.anthropic, 'hello')));
    final approvals = <NeuraModelProvider>[];
    final router = NeuraSecureModelRouter(
        credentials: credentials, streamTransports: [primary, fallback]);
    await expectLater(
        router.stream(request, tools: [], cancel: NeuraGenerationCancel('test'),
            requestApproval: (preview) async {
          approvals.add(preview.provider);
          return preview.provider == NeuraModelProvider.openAi;
        }).toList(),
        throwsA(isA<NeuraCloudApprovalDenied>()));
    expect(approvals, NeuraModelProvider.values);
    expect(fallback.calls, 0);
  });

  test('stream never switches providers after visible output', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    await credentials.save(NeuraModelProvider.anthropic, anthropicKey);
    final primary = _StreamTransport(NeuraModelProvider.openAi, () async* {
      yield const NeuraTextDelta(NeuraModelProvider.openAi, 'partial');
      throw const NeuraStreamFailure('disconnected');
    });
    final fallback = _StreamTransport(
        NeuraModelProvider.anthropic, () => const Stream.empty());
    final router = NeuraSecureModelRouter(
        credentials: credentials, streamTransports: [primary, fallback]);
    await expectLater(
        router
            .stream(request,
                tools: [],
                cancel: NeuraGenerationCancel('test'),
                requestApproval: (_) async => true)
            .toList(),
        throwsA(isA<NeuraStreamFailure>()));
    expect(fallback.calls, 0);
    expect(primary.calls, 1);
  });

  test('retryable stream failure gets one fresh-approved bounded retry',
      () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    var attempts = 0;
    final transport = _StreamTransport(NeuraModelProvider.openAi, () {
      attempts++;
      if (attempts == 1) {
        return Stream.error(const NeuraStreamFailure(
          'busy',
          statusCode: 429,
          kind: NeuraModelFailureKind.rateLimited,
          retryAfter: Duration(seconds: 2),
        ));
      }
      return Stream.value(
        const NeuraTextDelta(NeuraModelProvider.openAi, 'ready'),
      );
    });
    final approvals = <NeuraCloudRequestPreview>[];
    final delays = <Duration>[];
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      streamTransports: [transport],
      sleep: (delay, _) async => delays.add(delay),
    );

    final events = await router.stream(
      request,
      tools: [],
      cancel: NeuraGenerationCancel('retry'),
      requestApproval: (preview) async {
        approvals.add(preview);
        return true;
      },
    ).toList();

    expect(transport.calls, 2);
    expect(
      approvals.map((preview) => preview.provider),
      [NeuraModelProvider.openAi, NeuraModelProvider.openAi],
    );
    expect(approvals.first.approvalId, isNot(approvals.last.approvalId));
    expect(
      approvals.first.transaction.idempotencyKey,
      approvals.last.transaction.idempotencyKey,
    );
    expect(approvals.map((preview) => preview.retryCount), [0, 1]);
    expect(transport.transactions, hasLength(2));
    expect(delays, [const Duration(seconds: 2)]);
    expect((events.single as NeuraTextDelta).text, 'ready');
  });

  test('cancellation during retry backoff prevents the second request',
      () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport = _StreamTransport(
      NeuraModelProvider.openAi,
      () => Stream.error(const NeuraStreamFailure(
        'offline',
        kind: NeuraModelFailureKind.connection,
      )),
    );
    final cancel = NeuraGenerationCancel('cancel-backoff');
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      streamTransports: [transport],
      sleep: (_, token) async => token!.cancel(),
    );

    await expectLater(
      router
          .stream(
            request,
            tools: [],
            cancel: cancel,
            requestApproval: (_) async => true,
          )
          .toList(),
      throwsA(isA<NeuraGenerationCancelled>()),
    );
    expect(transport.calls, 1);
  });

  test('Safe Mode during retry backoff prevents the second request', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport = _StreamTransport(
      NeuraModelProvider.openAi,
      () => Stream.error(const NeuraStreamFailure(
        'offline',
        kind: NeuraModelFailureKind.connection,
      )),
    );
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      streamTransports: [transport],
      sleep: (_, __) async => SafeBoot.instance.safeMode.value = true,
    );

    await expectLater(
      router
          .stream(
            request,
            tools: [],
            cancel: NeuraGenerationCancel('safe-backoff'),
            requestApproval: (_) async => true,
          )
          .toList(),
      throwsA(isA<NeuraGenerationCancelled>()),
    );
    expect(transport.calls, 1);
  });

  test('tool continuation never retries or switches providers', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    await credentials.save(NeuraModelProvider.anthropic, anthropicKey);
    final primary = _StreamTransport(
      NeuraModelProvider.openAi,
      () => Stream.error(const NeuraStreamFailure(
        'offline',
        kind: NeuraModelFailureKind.connection,
      )),
    );
    final fallback = _StreamTransport(
      NeuraModelProvider.anthropic,
      () => Stream.value(
        const NeuraTextDelta(NeuraModelProvider.anthropic, 'unsafe replay'),
      ),
    );
    var approvals = 0;
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      streamTransports: [primary, fallback],
      sleep: (_, __) async {},
    );

    await expectLater(
      router.stream(
        request,
        tools: const [],
        cancel: NeuraGenerationCancel('tool-continuation'),
        provider: NeuraModelProvider.openAi,
        requestApproval: (_) async {
          approvals++;
          return true;
        },
      ).toList(),
      throwsA(isA<NeuraStreamFailure>()),
    );
    expect(approvals, 1);
    expect(primary.calls, 1);
    expect(fallback.calls, 0);
  });

  test('passive circuit opens without background provider probes', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport = _StreamTransport(
      NeuraModelProvider.openAi,
      () => Stream.error(const NeuraStreamFailure(
        'unavailable',
        kind: NeuraModelFailureKind.providerUnavailable,
      )),
    );
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      streamTransports: [transport],
      now: () => DateTime.utc(2026, 9, 23),
      sleep: (_, __) async {},
    );
    var approvals = 0;

    for (var index = 0; index < 2; index++) {
      await expectLater(
        router.stream(
          request,
          tools: const [],
          cancel: NeuraGenerationCancel('circuit-$index'),
          requestApproval: (_) async {
            approvals++;
            return true;
          },
        ).toList(),
        throwsA(isA<NeuraStreamFailure>()),
      );
    }
    expect(transport.calls, 4);
    expect(approvals, 4);
    expect(
      (router.providerHealthSnapshot['openAi'] as Map)['state'],
      'open',
    );

    await expectLater(
      router.stream(
        request,
        tools: const [],
        cancel: NeuraGenerationCancel('open-circuit'),
        requestApproval: (_) async {
          approvals++;
          return true;
        },
      ).toList(),
      throwsA(isA<NeuraProviderCircuitOpen>()),
    );
    expect(transport.calls, 4);
    expect(approvals, 4);
  });

  test('cancellation while approval is open prevents transport call', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport =
        _StreamTransport(NeuraModelProvider.openAi, () => const Stream.empty());
    final cancel = NeuraGenerationCancel('test');
    final router = NeuraSecureModelRouter(
        credentials: credentials, streamTransports: [transport]);
    await expectLater(
        router.stream(request, tools: [], cancel: cancel,
            requestApproval: (_) async {
          cancel.cancel();
          return true;
        }).toList(),
        throwsA(isA<NeuraGenerationCancelled>()));
    expect(transport.calls, 0);
  });

  test('Safe Mode during stream approval prevents transport call', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport =
        _StreamTransport(NeuraModelProvider.openAi, () => const Stream.empty());
    final router = NeuraSecureModelRouter(
        credentials: credentials, streamTransports: [transport]);
    await expectLater(
        router.stream(request, tools: [], cancel: NeuraGenerationCancel('test'),
            requestApproval: (_) async {
          SafeBoot.instance.safeMode.value = true;
          return true;
        }).toList(),
        throwsA(isA<NeuraGenerationCancelled>()));
    expect(transport.calls, 0);
  });

  test('OpenAI is the primary provider', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    await credentials.save(NeuraModelProvider.anthropic, anthropicKey);
    final openAi = _Transport(NeuraModelProvider.openAi, result: 'primary');
    final anthropic =
        _Transport(NeuraModelProvider.anthropic, result: 'fallback');
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi, anthropic],
    );

    final response = await router.complete(
      request,
      requestApproval: (_) async => true,
    );

    expect(response.provider, NeuraModelProvider.openAi);
    expect(response.text, 'primary');
    expect(openAi.calls, 1);
    expect(anthropic.calls, 0);
  });

  test('fallback requires a separate approval', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    await credentials.save(NeuraModelProvider.anthropic, anthropicKey);
    final openAi = _Transport(
      NeuraModelProvider.openAi,
      error: StateError('primary unavailable'),
    );
    final anthropic =
        _Transport(NeuraModelProvider.anthropic, result: 'fallback');
    final approvals = <NeuraModelProvider>[];
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi, anthropic],
    );

    await expectLater(
      router.complete(
        request,
        requestApproval: (preview) async {
          approvals.add(preview.provider);
          return preview.provider == NeuraModelProvider.openAi;
        },
      ),
      throwsA(isA<NeuraCloudApprovalDenied>()),
    );

    expect(
      approvals,
      [NeuraModelProvider.openAi, NeuraModelProvider.anthropic],
    );
    expect(openAi.calls, 1);
    expect(anthropic.calls, 0);
  });

  test('atomic completion retry also requires a fresh approval', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final openAi = _SequenceTransport(NeuraModelProvider.openAi, [
      const NeuraModelTransportException(
        NeuraModelProvider.openAi,
        503,
        'unavailable',
        kind: NeuraModelFailureKind.providerUnavailable,
      ),
      'recovered',
    ]);
    var approvals = 0;
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi],
      sleep: (_, __) async {},
    );

    final response = await router.complete(
      request,
      requestApproval: (_) async {
        approvals++;
        return true;
      },
    );

    expect(response.text, 'recovered');
    expect(openAi.calls, 2);
    expect(approvals, 2);
  });

  test('request budget keeps a contiguous recent suffix and reports omission',
      () {
    final bounded = NeuraModelRequestBudget.freezeAndApply(
      NeuraModelRequest(
        systemPrompt: 'safe',
        messages: [
          for (var index = 0; index < 60; index++)
            {'role': 'user', 'content': 'turn-$index'},
        ],
        purpose: 'chat reply',
        includesPrivateContext: false,
      ),
    );

    expect(bounded.messages, hasLength(NeuraModelRequestBudget.maxMessages));
    expect(bounded.messages.first['content'], 'turn-12');
    expect(bounded.messages.last['content'], 'turn-59');
    expect(bounded.omittedMessageCount, 12);
    expect(
      bounded
          .previewFor(
            NeuraModelProvider.openAi,
            _transactionFor(NeuraModelProvider.openAi),
          )
          .omittedMessageCount,
      12,
    );
  });

  test('request budget fails before approval when latest content is oversized',
      () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport =
        _StreamTransport(NeuraModelProvider.openAi, () => const Stream.empty());
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      streamTransports: [transport],
    );
    var approvals = 0;
    final oversized = NeuraModelRequest(
      systemPrompt: 'safe',
      messages: [
        {
          'role': 'user',
          'content': List.filled(
            NeuraModelRequestBudget.maxTextCharacters + 1,
            'x',
          ).join(),
        },
      ],
      purpose: 'chat reply',
      includesPrivateContext: false,
    );

    await expectLater(
      router.stream(
        oversized,
        tools: [],
        cancel: NeuraGenerationCancel('oversized'),
        requestApproval: (_) async {
          approvals++;
          return true;
        },
      ).toList(),
      throwsA(isA<NeuraRequestBudgetExceeded>()),
    );
    expect(approvals, 0);
    expect(transport.calls, 0);
  });

  test('denial prevents all network transport calls', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final openAi = _Transport(NeuraModelProvider.openAi, result: 'unused');
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi],
    );

    await expectLater(
      router.complete(request, requestApproval: (_) async => false),
      throwsA(isA<NeuraCloudApprovalDenied>()),
    );
    expect(openAi.calls, 0);
  });

  test('Safe Mode blocks before approval or transport', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final openAi = _Transport(NeuraModelProvider.openAi, result: 'unused');
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi],
    );
    var approvalCalls = 0;
    SafeBoot.instance.safeMode.value = true;

    await expectLater(
      router.complete(
        request,
        requestApproval: (_) async {
          approvalCalls++;
          return true;
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(approvalCalls, 0);
    expect(openAi.calls, 0);
  });

  test('Safe Mode after a response prevents fallback and disclosure', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    await credentials.save(NeuraModelProvider.anthropic, anthropicKey);
    final openAi = _Transport(
      NeuraModelProvider.openAi,
      result: 'must not be returned',
      onComplete: () => SafeBoot.instance.safeMode.value = true,
    );
    final anthropic = _Transport(
      NeuraModelProvider.anthropic,
      result: 'must not be requested',
    );
    final approvals = <NeuraModelProvider>[];
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi, anthropic],
    );

    await expectLater(
      router.complete(
        request,
        requestApproval: (preview) async {
          approvals.add(preview.provider);
          return true;
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(approvals, [NeuraModelProvider.openAi]);
    expect(openAi.calls, 1);
    expect(anthropic.calls, 0);
  });

  test('the default constitution allows cloud requests', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final openAi = _Transport(NeuraModelProvider.openAi, result: 'ok');
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi],
      constitution: const NeuraPersonalConstitution(),
    );

    final response = await router.complete(
      request,
      requestApproval: (_) async => true,
    );

    expect(response.text, 'ok');
  });

  test('production router observes a constitution tightened after creation',
      () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final openAi = _Transport(NeuraModelProvider.openAi, result: 'unused');
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi],
    );
    await NeuraConstitutionService.instance.save(
      const NeuraPersonalConstitution(allowCloudAi: false),
    );
    var approvalCalls = 0;

    await expectLater(
      router.complete(
        request,
        requestApproval: (_) async {
          approvalCalls++;
          return true;
        },
      ),
      throwsA(isA<NeuraConstitutionBlocked>()),
    );

    expect(approvalCalls, 0);
    expect(openAi.calls, 0);
  });

  test('constitution tightening after primary failure prevents fallback',
      () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    await credentials.save(NeuraModelProvider.anthropic, anthropicKey);
    final openAi = _Transport(
      NeuraModelProvider.openAi,
      error: StateError('primary unavailable'),
      onComplete: () {
        unawaited(
          NeuraConstitutionService.instance.save(
            const NeuraPersonalConstitution(allowCloudAi: false),
          ),
        );
      },
    );
    final anthropic =
        _Transport(NeuraModelProvider.anthropic, result: 'unused');
    final approvals = <NeuraModelProvider>[];
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi, anthropic],
    );

    await expectLater(
      router.complete(
        request,
        requestApproval: (preview) async {
          approvals.add(preview.provider);
          return true;
        },
      ),
      throwsA(isA<NeuraConstitutionBlocked>()),
    );

    expect(approvals, [NeuraModelProvider.openAi]);
    expect(openAi.calls, 1);
    expect(anthropic.calls, 0);
  });

  test(
      'an explicitly locked-down constitution blocks the request before '
      'approval or transport', () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final openAi = _Transport(NeuraModelProvider.openAi, result: 'unused');
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi],
      constitution: const NeuraPersonalConstitution(allowCloudAi: false),
    );
    var approvalCalls = 0;

    await expectLater(
      router.complete(
        request,
        requestApproval: (_) async {
          approvalCalls++;
          return true;
        },
      ),
      throwsA(isA<NeuraConstitutionBlocked>()),
    );

    expect(approvalCalls, 0);
    expect(openAi.calls, 0);
  });

  test('sensitive content is blocked from the cloud even with cloud AI on',
      () async {
    const sensitiveRequest = NeuraModelRequest(
      systemPrompt: 'Be kind.',
      messages: [
        {'role': 'user', 'content': 'Hello'},
      ],
      purpose: 'chat reply',
      includesPrivateContext: true,
    );
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final openAi = _Transport(NeuraModelProvider.openAi, result: 'unused');
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [openAi],
      constitution: const NeuraPersonalConstitution(), // keepSensitive: true
    );

    await expectLater(
      router.complete(
        sensitiveRequest,
        requestApproval: (_) async => true,
      ),
      throwsA(isA<NeuraConstitutionBlocked>()),
    );
    expect(openAi.calls, 0);
  });

  test('private streamed history is blocked before approval or transport',
      () async {
    const privateHistory = NeuraModelRequest(
      systemPrompt: 'Be kind.',
      messages: [
        {'role': 'assistant', 'content': 'A reply based on a selected file.'},
        {'role': 'user', 'content': 'Explain the last answer.'},
      ],
      purpose: 'chat reply',
      includesPrivateContext: true,
    );
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport =
        _StreamTransport(NeuraModelProvider.openAi, () => const Stream.empty());
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      streamTransports: [transport],
      constitution: const NeuraPersonalConstitution(),
    );
    var approvals = 0;
    await expectLater(
      router.stream(privateHistory,
          tools: [], cancel: NeuraGenerationCancel('private-history'),
          requestApproval: (_) async {
        approvals++;
        return true;
      }).toList(),
      throwsA(isA<NeuraConstitutionBlocked>()),
    );
    expect(approvals, 0);
    expect(transport.calls, 0);
  });

  test('private stream rechecks local-only policy after approval', () async {
    await NeuraConstitutionService.instance.save(
      const NeuraPersonalConstitution(keepSensitiveContentLocal: false),
    );
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport =
        _StreamTransport(NeuraModelProvider.openAi, () => const Stream.empty());
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      streamTransports: [transport],
    );
    const privateRequest = NeuraModelRequest(
      systemPrompt: 'Be kind.',
      messages: [
        {'role': 'assistant', 'content': 'A reply based on permitted memory.'},
        {'role': 'user', 'content': 'Tell me more.'},
      ],
      purpose: 'chat reply',
      includesPrivateContext: true,
    );
    var approvals = 0;
    await expectLater(
      router.stream(privateRequest,
          tools: [], cancel: NeuraGenerationCancel('private-revocation'),
          requestApproval: (preview) async {
        approvals++;
        expect(preview.includesPrivateContext, isTrue);
        expect(preview.textPreview, contains('permitted memory'));
        await NeuraConstitutionService.instance.save(
          const NeuraPersonalConstitution(keepSensitiveContentLocal: true),
        );
        return true;
      }).toList(),
      throwsA(isA<NeuraConstitutionBlocked>()),
    );
    expect(approvals, 1);
    expect(transport.calls, 0);
  });

  test('fallback is a new audience-bound transaction on the same trace',
      () async {
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    await credentials.save(NeuraModelProvider.anthropic, anthropicKey);
    final primary = _Transport(
      NeuraModelProvider.openAi,
      error: StateError('unavailable'),
    );
    final fallback = _Transport(
      NeuraModelProvider.anthropic,
      result: 'fallback',
    );
    final previews = <NeuraCloudRequestPreview>[];
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [primary, fallback],
    );

    final response = await router.complete(
      request,
      requestApproval: (preview) async {
        previews.add(preview);
        return true;
      },
    );

    expect(response.provider, NeuraModelProvider.anthropic);
    expect(previews, hasLength(2));
    expect(previews.first.traceId, previews.last.traceId);
    expect(
      previews.first.transaction.idempotencyKey,
      isNot(previews.last.transaction.idempotencyKey),
    );
    expect(previews.first.audience.host, 'api.openai.com');
    expect(previews.last.audience.host, 'api.anthropic.com');
  });

  test('audit trail records trace metadata without prompt or digest', () async {
    const privateWords = 'do-not-log-these-private-words';
    const privateRequest = NeuraModelRequest(
      systemPrompt: 'Be kind.',
      messages: [
        {'role': 'user', 'content': privateWords},
      ],
      purpose: 'chat reply',
      includesPrivateContext: false,
    );
    final credentials = NeuraModelCredentials.forTesting(_MemoryStorage());
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    final transport = _Transport(
      NeuraModelProvider.openAi,
      result: 'ok',
    );
    final router = NeuraSecureModelRouter(
      credentials: credentials,
      transports: [transport],
    );
    late NeuraCloudRequestPreview preview;

    await router.complete(
      privateRequest,
      requestApproval: (value) async {
        preview = value;
        return true;
      },
    );

    final encoded = router.cloudAuditSnapshot.toString();
    expect(encoded, contains(preview.traceId));
    expect(encoded, isNot(contains(privateWords)));
    expect(encoded, isNot(contains(preview.promptDigest)));
  });

  test('credential deletion is verified', () async {
    final storage = _MemoryStorage();
    final credentials = NeuraModelCredentials.forTesting(storage);
    await credentials.save(NeuraModelProvider.openAi, openAiKey);
    expect(await credentials.read(NeuraModelProvider.openAi), isNotNull);

    await credentials.clear(NeuraModelProvider.openAi);

    expect(await credentials.read(NeuraModelProvider.openAi), isNull);
    expect(
      credentials.configured.value,
      isNot(contains(NeuraModelProvider.openAi)),
    );
  });
}
