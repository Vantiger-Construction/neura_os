import 'package:flutter/foundation.dart';

enum SyncReadinessState {
  ready,
  safeMode,
  notConfigured,
  clientUnavailable,
}

@immutable
class SyncReadiness {
  const SyncReadiness({
    required this.state,
    required this.title,
    required this.detail,
  });

  final SyncReadinessState state;
  final String title;
  final String detail;

  bool get canSync => state == SyncReadinessState.ready;
}

SyncReadiness evaluateSyncReadiness({
  required bool configured,
  required bool safeMode,
  required bool clientAvailable,
}) {
  if (safeMode) {
    return const SyncReadiness(
      state: SyncReadinessState.safeMode,
      title: 'Safe Mode: local only',
      detail: 'Cloud initialization and synchronization are disabled.',
    );
  }
  if (!configured) {
    return const SyncReadiness(
      state: SyncReadinessState.notConfigured,
      title: 'Local-only mode',
      detail: 'No Supabase client configuration is present in this build.',
    );
  }
  if (!clientAvailable) {
    return const SyncReadiness(
      state: SyncReadinessState.clientUnavailable,
      title: 'Cloud unavailable',
      detail: 'Optional cloud startup did not produce a usable client.',
    );
  }
  return const SyncReadiness(
    state: SyncReadinessState.ready,
    title: 'Ready to sync',
    detail: 'Local entries remain available before, during, and after sync.',
  );
}
