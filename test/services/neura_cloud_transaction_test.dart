import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_cloud_transaction.dart';
import 'package:neuro_companion/services/neura_model_types.dart';

void main() {
  test('binds provider, audience, retry, and no-store headers', () async {
    var next = 0;
    final factory = NeuraCloudTransactionFactory(
      idFactory: () => 'id-${next++}',
    );

    final envelope = await factory.create(
      provider: NeuraModelProvider.openAi,
      canonicalPayload: '{"messages":["hello"]}',
      traceId: factory.newTraceId(),
      idempotencyKey: factory.newIdempotencyKey(),
      retryCount: 0,
    );

    expect(envelope.approvalState, NeuraCloudApprovalState.inputRequired);
    expect(envelope.promptDigest, hasLength(64));
    expect(envelope.privateCacheProhibited, isTrue);
    expect(
      envelope.requestHeaders(),
      containsPair('cache-control', 'no-store'),
    );
    expect(
      envelope.requestHeaders(),
      containsPair('idempotency-key', envelope.idempotencyKey),
    );
    expect(
      () => envelope.validateFor(
        requestedProvider: NeuraModelProvider.anthropic,
        requestedAudience: NeuraCloudTransactionEnvelope.audienceFor(
          NeuraModelProvider.anthropic,
        ),
      ),
      throwsStateError,
    );
  });

  test('fresh approval IDs share idempotency only for exact retries', () async {
    var next = 0;
    final factory = NeuraCloudTransactionFactory(
      idFactory: () => 'id-${next++}',
    );
    final traceId = factory.newTraceId();
    final idempotencyKey = factory.newIdempotencyKey();

    final first = await factory.create(
      provider: NeuraModelProvider.openAi,
      canonicalPayload: 'same',
      traceId: traceId,
      idempotencyKey: idempotencyKey,
      retryCount: 0,
    );
    final retry = await factory.create(
      provider: NeuraModelProvider.openAi,
      canonicalPayload: 'same',
      traceId: traceId,
      idempotencyKey: idempotencyKey,
      retryCount: 1,
    );

    expect(retry.approvalId, isNot(first.approvalId));
    expect(retry.traceId, first.traceId);
    expect(retry.idempotencyKey, first.idempotencyKey);
    expect(retry.promptDigest, first.promptDigest);
    expect(retry.isRetry, isTrue);
  });

  test(
    'audit trail contains metadata but exposes no prompt or digest key',
    () async {
      var next = 0;
      final factory = NeuraCloudTransactionFactory(
        idFactory: () => 'id-${next++}',
      );
      final envelope = await factory.create(
        provider: NeuraModelProvider.anthropic,
        canonicalPayload: 'private prompt text',
        traceId: factory.newTraceId(),
        idempotencyKey: factory.newIdempotencyKey(),
        retryCount: 0,
      );
      final audit = NeuraCloudAuditTrail(capacity: 2);

      audit.record(envelope, NeuraCloudAuditStage.approvalRequired);
      audit.record(envelope, NeuraCloudAuditStage.approved);
      audit.record(envelope, NeuraCloudAuditStage.sent);

      expect(audit.events, hasLength(2));
      final encoded = audit.events.last.toJson().toString();
      expect(encoded, isNot(contains('private prompt text')));
      expect(encoded, isNot(contains(envelope.promptDigest)));
      expect(encoded, contains(envelope.traceId));
    },
  );

  test('audit retention must be explicitly bounded', () {
    expect(() => NeuraCloudAuditTrail(capacity: 0), throwsRangeError);
    expect(() => NeuraCloudAuditTrail(capacity: 1001), throwsRangeError);
  });
}
