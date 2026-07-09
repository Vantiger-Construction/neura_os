import 'package:neuro_companion/models/usage_entry.dart';

class UsageRepository {
  final List<UsageEntry> _entries = [];

  // Get all usage entries
  List<UsageEntry> getAllEntries() {
    return List.unmodifiable(_entries);
  }

  // Add a new usage entry
  void addEntry(UsageEntry entry) {
    _entries.add(entry);
  }

  // Delete an entry by id
  void deleteEntry(String id) {
    _entries.removeWhere((entry) => entry.id == id);
  }

  // Add other methods as needed, e.g., updateEntry, etc.
}
