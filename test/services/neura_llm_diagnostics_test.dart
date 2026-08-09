import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_llm_diagnostics.dart';

void main() {
  final diagnostics = NeuraLlmDiagnostics.instance;

  setUp(diagnostics.resetForTesting);

  test('snapshot tracks failures retries and recovery', () {
    diagnostics.recordAttempt();
    diagnostics.recordRetry();
    diagnostics.recordFailure(StateError('offline'));

    var snapshot = diagnostics.snapshot();
    expect(snapshot['healthy'], isFalse);
    expect(snapshot['attempts'], 1);
    expect(snapshot['retries'], 1);
    expect(snapshot['failures'], 1);
    expect(snapshot['last_error'], contains('offline'));

    diagnostics.recordAttempt();
    diagnostics.recordSuccess();
    diagnostics.recordCancellation();
    diagnostics.recordToolDrop();
    diagnostics.recordFallback();

    snapshot = diagnostics.snapshot();
    expect(snapshot['healthy'], isTrue);
    expect(snapshot['successes'], 1);
    expect(snapshot['cancellations'], 1);
    expect(snapshot['tool_drops'], 1);
    expect(snapshot['fallbacks'], 1);
    expect(snapshot['last_error'], isNull);
  });
}
