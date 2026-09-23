/// Shared health counters for Neura's primary LLM responder.
///
/// Counters are intentionally process-local and contain no conversation text.
/// They are safe to surface in a diagnostics UI or log snapshot.
class NeuraLlmDiagnostics {
  NeuraLlmDiagnostics._();
  static final NeuraLlmDiagnostics instance = NeuraLlmDiagnostics._();

  int attempts = 0;
  int successes = 0;
  int failures = 0;
  int retries = 0;
  int cancellations = 0;
  int toolDrops = 0;
  int fallbacks = 0;
  int providerFallbacks = 0;
  int contextMessagesOmitted = 0;
  DateTime? lastAttemptAt;
  DateTime? lastSuccessAt;
  DateTime? lastFailureAt;
  String? lastError;
  int? lastFirstTokenMs;
  int? lastCompletionMs;

  bool get healthy =>
      failures == 0 ||
      (lastSuccessAt != null &&
          (lastFailureAt == null || lastSuccessAt!.isAfter(lastFailureAt!)));

  void recordAttempt() {
    attempts += 1;
    lastAttemptAt = DateTime.now();
  }

  void recordSuccess() {
    successes += 1;
    lastSuccessAt = DateTime.now();
    lastError = null;
  }

  void recordFailure(Object error) {
    failures += 1;
    lastFailureAt = DateTime.now();
    // Provider exceptions may echo prompts, credentials, URLs, or local
    // paths. Diagnostics only needs a stable classification; arbitrary
    // exception text must never cross into logs or the UI.
    lastError = '${error.runtimeType} details withheld.';
  }

  void recordRetry() => retries += 1;
  void recordCancellation() => cancellations += 1;
  void recordToolDrop() => toolDrops += 1;
  void recordFallback() => fallbacks += 1;
  void recordProviderFallback() => providerFallbacks += 1;

  void recordContextOmission(int count) {
    if (count > 0) contextMessagesOmitted += count;
  }

  void recordFirstToken(Duration elapsed) {
    lastFirstTokenMs = elapsed.inMilliseconds;
  }

  void recordCompletion(Duration elapsed) {
    lastCompletionMs = elapsed.inMilliseconds;
  }

  Map<String, dynamic> snapshot() {
    final isHealthy = healthy;
    return {
      'healthy': isHealthy,
      'attempts': attempts,
      'successes': successes,
      'failures': failures,
      'retries': retries,
      'cancellations': cancellations,
      'tool_drops': toolDrops,
      'fallbacks': fallbacks,
      'provider_fallbacks': providerFallbacks,
      'context_messages_omitted': contextMessagesOmitted,
      'last_first_token_ms': lastFirstTokenMs,
      'last_completion_ms': lastCompletionMs,
      'last_attempt_at': lastAttemptAt?.toIso8601String(),
      'last_success_at': lastSuccessAt?.toIso8601String(),
      'last_failure_at': lastFailureAt?.toIso8601String(),
      'last_error': lastError,
      'remedy': isHealthy
          ? 'LLM responder is healthy.'
          : 'Check network access and configured model credentials, then retry.',
    };
  }

  /// Test-only convenience. Production code should never need to clear health
  /// history during a process lifetime.
  void resetForTesting() {
    resetAfterDataWipe();
  }

  void resetAfterDataWipe() {
    attempts = 0;
    successes = 0;
    failures = 0;
    retries = 0;
    cancellations = 0;
    toolDrops = 0;
    fallbacks = 0;
    providerFallbacks = 0;
    contextMessagesOmitted = 0;
    lastAttemptAt = null;
    lastSuccessAt = null;
    lastFailureAt = null;
    lastError = null;
    lastFirstTokenMs = null;
    lastCompletionMs = null;
  }
}
