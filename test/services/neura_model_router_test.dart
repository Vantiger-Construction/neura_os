import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_model_credentials.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_model_types.dart';

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

class _Transport implements NeuraModelTransport {
  _Transport(this.provider, {this.result, this.error, this.onComplete});

  @override
  final NeuraModelProvider provider;
  final String? result;
  final Object? error;
  final void Function()? onComplete;
  int calls = 0;

  @override
  Future<String> complete({
    required String apiKey,
    required NeuraModelRequest request,
  }) async {
    calls++;
    onComplete?.call();
    if (error != null) throw error!;
    return result!;
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

  setUp(() {
    originalSafeMode = SafeBoot.instance.safeMode.value;
    SafeBoot.instance.safeMode.value = false;
  });

  tearDown(() {
    SafeBoot.instance.safeMode.value = originalSafeMode;
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
