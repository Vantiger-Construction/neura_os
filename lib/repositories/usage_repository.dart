import 'package:neura_companion/models/usage_entry.dart';

class UsageRepository {
  // Simulated data store (replace with actual database/API logic as needed)
  final List<UsageEntry> _entries = [
    // Example entries; remove or replace with real data
    UsageEntry(
      id: '1',
      timestamp: DateTime.now(),
      type: 'example_type',
      source: 'example_source',
      moodTag: 'neutral',
    ),
  ];

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
