import '../models/journal_entry.dart';

class ConflictResolutionService {
  /// Presents conflict data and resolves based on user choice.
  Future<JournalEntry> resolve(JournalEntry local, JournalEntry remote) async {
    // TODO: present UI to choose local vs remote or merge
    return local; // default to local
  }
}
