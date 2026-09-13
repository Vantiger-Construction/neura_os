import '../models/journal_entry.dart';

enum ConflictWinner { local, remote, equivalent }

class ConflictResolutionDecision {
  const ConflictResolutionDecision({
    required this.entry,
    required this.winner,
    required this.hadDivergentContent,
  });

  final JournalEntry entry;
  final ConflictWinner winner;
  final bool hadDivergentContent;
}

class ConflictResolutionService {
  /// Resolves two revisions of the same journal entry using their modification
  /// timestamps. Equal-time divergent revisions prefer local data so an
  /// optional cloud backend can never silently overwrite the local-first copy.
  ConflictResolutionDecision decide(
    JournalEntry local,
    JournalEntry remote,
  ) {
    final localUpdated = local.effectiveUpdatedAt.toUtc();
    final remoteUpdated = remote.effectiveUpdatedAt.toUtc();
    final divergent = !_samePayload(local, remote);

    if (remoteUpdated.isAfter(localUpdated)) {
      return ConflictResolutionDecision(
        entry: remote,
        winner: ConflictWinner.remote,
        hadDivergentContent: divergent,
      );
    }
    if (localUpdated.isAfter(remoteUpdated)) {
      return ConflictResolutionDecision(
        entry: local,
        winner: ConflictWinner.local,
        hadDivergentContent: divergent,
      );
    }
    if (!divergent) {
      return ConflictResolutionDecision(
        entry: local,
        winner: ConflictWinner.equivalent,
        hadDivergentContent: false,
      );
    }
    return ConflictResolutionDecision(
      entry: local,
      winner: ConflictWinner.local,
      hadDivergentContent: true,
    );
  }

  Future<JournalEntry> resolve(
    JournalEntry local,
    JournalEntry remote,
  ) async {
    return decide(local, remote).entry;
  }

  bool _samePayload(JournalEntry left, JournalEntry right) {
    return left.content == right.content &&
        left.moodTag == right.moodTag &&
        left.isVoice == right.isVoice;
  }
}
