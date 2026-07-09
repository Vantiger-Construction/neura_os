import '../models/journal_entry.dart';

class ConflictResolutionService {
  /// Resolves a sync conflict between [local] and [remote] entries with the
  /// same ID by returning whichever has the more recent timestamp.
  /// Both entries have equal standing — this is a last-write-wins policy.
  Future<JournalEntry> resolve(JournalEntry local, JournalEntry remote) async {
    return remote.timestamp.isAfter(local.timestamp) ? remote : local;
  }
}
