import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/sync_readiness.dart';

void main() {
  test('Safe Mode is the strongest sync boundary', () {
    final readiness = evaluateSyncReadiness(
      configured: true,
      safeMode: true,
      clientAvailable: true,
    );

    expect(readiness.state, SyncReadinessState.safeMode);
    expect(readiness.canSync, isFalse);
  });

  test('missing configuration reports local-only mode', () {
    final readiness = evaluateSyncReadiness(
      configured: false,
      safeMode: false,
      clientAvailable: false,
    );

    expect(readiness.state, SyncReadinessState.notConfigured);
    expect(readiness.canSync, isFalse);
  });

  test('configured but unavailable client cannot sync', () {
    final readiness = evaluateSyncReadiness(
      configured: true,
      safeMode: false,
      clientAvailable: false,
    );

    expect(readiness.state, SyncReadinessState.clientUnavailable);
    expect(readiness.canSync, isFalse);
  });

  test('sync is enabled only across every boundary', () {
    final readiness = evaluateSyncReadiness(
      configured: true,
      safeMode: false,
      clientAvailable: true,
    );

    expect(readiness.state, SyncReadinessState.ready);
    expect(readiness.canSync, isTrue);
  });
}
