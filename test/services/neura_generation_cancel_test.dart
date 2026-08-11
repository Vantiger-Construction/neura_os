import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';

void main() {
  test('cancel is idempotent and throws with generation id', () async {
    final cancel = NeuraGenerationCancel('reply-42');
    expect(cancel.isCancelled, isFalse);

    cancel.cancel();
    cancel.cancel();

    expect(cancel.isCancelled, isTrue);
    await expectLater(cancel.whenCancelled, completes);
    expect(
      cancel.throwIfCancelled,
      throwsA(
        isA<NeuraGenerationCancelled>().having(
          (e) => e.generationId,
          'generationId',
          'reply-42',
        ),
      ),
    );
  });

  test('backoff delay exits early when cancelled', () async {
    final cancel = NeuraGenerationCancel('reply-43');
    final future = cancel.delay(const Duration(seconds: 5));
    cancel.cancel();

    await expectLater(future, throwsA(isA<NeuraGenerationCancelled>()));
  });
}
