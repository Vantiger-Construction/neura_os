import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'neura_model_types.dart';

enum NeuraCloudApprovalState { inputRequired }

enum NeuraCloudAuditStage {
  approvalRequired,
  approved,
  denied,
  sent,
  succeeded,
  failed,
}

typedef NeuraCloudIdFactory = String Function();

/// One immutable, provider-bound outbound attempt.
///
/// The prompt digest binds the approval preview to the exact logical payload.
/// It is never placed in an HTTP header or written to the audit trail.
final class NeuraCloudTransactionEnvelope {
  NeuraCloudTransactionEnvelope({
    required this.approvalId,
    required this.traceId,
    required this.idempotencyKey,
    required this.promptDigest,
    required this.provider,
    required this.audience,
    required this.retryCount,
    this.approvalState = NeuraCloudApprovalState.inputRequired,
    this.privateCacheProhibited = true,
  }) {
    _requireId(approvalId, 'approval_id');
    _requireId(traceId, 'trace_id');
    _requireId(idempotencyKey, 'idempotency_key');
    if (!_sha256.hasMatch(promptDigest)) {
      throw const FormatException('Invalid cloud prompt digest.');
    }
    if (retryCount < 0 || retryCount > 1) {
      throw const FormatException('Invalid cloud retry count.');
    }
    if (audience != audienceFor(provider)) {
      throw const FormatException('Cloud audience does not match provider.');
    }
    if (!privateCacheProhibited) {
      throw const FormatException('Shared cloud caching must be prohibited.');
    }
  }

  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  final String approvalId;
  final String traceId;
  final String idempotencyKey;
  final String promptDigest;
  final NeuraModelProvider provider;
  final Uri audience;
  final int retryCount;
  final NeuraCloudApprovalState approvalState;
  final bool privateCacheProhibited;

  bool get isRetry => retryCount > 0;

  static Uri audienceFor(NeuraModelProvider provider) => switch (provider) {
        NeuraModelProvider.openAi =>
          Uri.parse('https://api.openai.com/v1/responses'),
        NeuraModelProvider.anthropic =>
          Uri.parse('https://api.anthropic.com/v1/messages'),
      };

  void validateFor({
    required NeuraModelProvider requestedProvider,
    required Uri requestedAudience,
  }) {
    if (requestedProvider != provider || requestedAudience != audience) {
      throw StateError('Cloud transaction provider or audience mismatch.');
    }
    if (!privateCacheProhibited ||
        approvalState != NeuraCloudApprovalState.inputRequired) {
      throw StateError('Cloud transaction policy is not sendable.');
    }
  }

  /// Headers carry operational identifiers only. Prompt text and its digest
  /// intentionally remain process-local.
  Map<String, String> requestHeaders() => {
        'cache-control': 'no-store',
        'pragma': 'no-cache',
        'idempotency-key': idempotencyKey,
        'x-neura-approval-id': approvalId,
        'x-neura-trace-id': traceId,
      };

  static void _requireId(String value, String name) {
    if (value.isEmpty ||
        value.length > 128 ||
        value.trim() != value ||
        value.codeUnits.any((unit) => unit < 0x21 || unit == 0x7f)) {
      throw FormatException('Invalid cloud $name.');
    }
  }
}

/// Creates fresh approval envelopes while preserving the logical idempotency
/// key across an exact retry to the same provider.
final class NeuraCloudTransactionFactory {
  NeuraCloudTransactionFactory({
    NeuraCloudIdFactory? idFactory,
    Sha256? sha256,
  })  : _idFactory = idFactory ?? (const Uuid()).v4,
        _sha256 = sha256 ?? Sha256();

  final NeuraCloudIdFactory _idFactory;
  final Sha256 _sha256;

  String newTraceId() => _idFactory();
  String newIdempotencyKey() => _idFactory();

  Future<NeuraCloudTransactionEnvelope> create({
    required NeuraModelProvider provider,
    required String canonicalPayload,
    required String traceId,
    required String idempotencyKey,
    required int retryCount,
  }) async {
    final hash = await _sha256.hash(utf8.encode(canonicalPayload));
    final digest = hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return NeuraCloudTransactionEnvelope(
      approvalId: _idFactory(),
      traceId: traceId,
      idempotencyKey: idempotencyKey,
      promptDigest: digest,
      provider: provider,
      audience: NeuraCloudTransactionEnvelope.audienceFor(provider),
      retryCount: retryCount,
    );
  }
}

/// Bounded, process-local audit metadata. No prompt, response, credential,
/// local path, or digest field exists in this event type.
final class NeuraCloudAuditEvent {
  const NeuraCloudAuditEvent({
    required this.traceId,
    required this.approvalId,
    required this.provider,
    required this.audience,
    required this.retryCount,
    required this.stage,
    required this.atUtc,
    this.failureKind,
  });

  final String traceId;
  final String approvalId;
  final NeuraModelProvider provider;
  final Uri audience;
  final int retryCount;
  final NeuraCloudAuditStage stage;
  final DateTime atUtc;
  final String? failureKind;

  Map<String, Object?> toJson() => {
        'trace_id': traceId,
        'approval_id': approvalId,
        'provider': provider.name,
        'audience': audience.host,
        'retry_count': retryCount,
        'stage': stage.name,
        'at_utc': atUtc.toIso8601String(),
        'failure_kind': failureKind,
      };
}

final class NeuraCloudAuditTrail {
  NeuraCloudAuditTrail({this.capacity = 100}) {
    if (capacity < 1 || capacity > 1000) {
      throw RangeError.range(capacity, 1, 1000, 'capacity');
    }
  }

  final int capacity;
  final List<NeuraCloudAuditEvent> _events = [];

  List<NeuraCloudAuditEvent> get events => List.unmodifiable(_events);

  void record(
    NeuraCloudTransactionEnvelope envelope,
    NeuraCloudAuditStage stage, {
    DateTime? atUtc,
    String? failureKind,
  }) {
    final event = NeuraCloudAuditEvent(
      traceId: envelope.traceId,
      approvalId: envelope.approvalId,
      provider: envelope.provider,
      audience: envelope.audience,
      retryCount: envelope.retryCount,
      stage: stage,
      atUtc: (atUtc ?? DateTime.now()).toUtc(),
      failureKind: failureKind,
    );
    _events.add(event);
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
  }

  void clear() => _events.clear();
}
