enum SyncOutcome {
  complete,
  offline,
  unavailable,
  signedOut,
  interrupted,
  retryNeeded,
  setupRequired,
  failed
}

class SyncResult {
  const SyncResult(this.outcome, {this.pending = 0});
  final SyncOutcome outcome;
  final int pending;
  bool get succeeded => outcome == SyncOutcome.complete;
  String get message => switch (outcome) {
        SyncOutcome.complete =>
          'Sync completed. Your local journal is available on this device.',
        SyncOutcome.offline =>
          'Offline. Your local changes are safe; retry when connected.',
        SyncOutcome.unavailable =>
          'Cloud sync is unavailable in this mode. Your journal stays local.',
        SyncOutcome.signedOut =>
          'Sign in before syncing. Your journal stays local.',
        SyncOutcome.interrupted =>
          'Sync stopped because the mode or account changed. Retry after checking your account.',
        SyncOutcome.retryNeeded =>
          'New local edits were kept. Tap Sync now to finish syncing them.',
        SyncOutcome.setupRequired =>
          'The cloud needs the revision-safe sync migration. Your journal stays local.',
        SyncOutcome.failed =>
          'Sync could not finish. Local entries were kept; tap Sync now to retry.',
      };
}

/// An acknowledgement may only replace the exact local revision sent.
/// A concurrent edit (or deletion) remains authoritative even if the server
/// assigned a later timestamp to an older upload.
bool mayApplySyncAcknowledgement(
        {required String? currentRevision, required String sentRevision}) =>
    currentRevision != null && currentRevision == sentRevision;

/// Coalesces concurrent manual requests; does not create a background worker.
class SyncSingleFlight {
  Future<SyncResult>? _active;
  Future<SyncResult> run(Future<SyncResult> Function() operation) {
    final active = _active;
    if (active != null) return active;
    late final Future<SyncResult> next;
    next = Future<SyncResult>.sync(operation).whenComplete(() {
      if (identical(_active, next)) _active = null;
    });
    _active = next;
    return next;
  }
}
