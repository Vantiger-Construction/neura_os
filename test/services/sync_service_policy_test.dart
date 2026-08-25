import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/sync_service.dart';

void main() {
  test('cloud sync requires configuration, normal mode, and a live client', () {
    expect(
      shouldAttemptCloudSync(
        configured: true,
        safeMode: false,
        clientAvailable: true,
      ),
      isTrue,
    );
    expect(
      shouldAttemptCloudSync(
        configured: true,
        safeMode: true,
        clientAvailable: true,
      ),
      isFalse,
    );
    expect(
      shouldAttemptCloudSync(
        configured: true,
        safeMode: false,
        clientAvailable: false,
      ),
      isFalse,
    );
    expect(
      shouldAttemptCloudSync(
        configured: false,
        safeMode: false,
        clientAvailable: true,
      ),
      isFalse,
    );
  });
}
