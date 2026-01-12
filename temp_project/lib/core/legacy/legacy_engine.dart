import 'legacy_entry.dart';

class LegacyEngine {
  final List<LegacyEntry> _entries = [];

  void record(String message) {
    _entries.add(LegacyEntry(
      created: DateTime.now(),
      message: message,
    ));
  }

  List<LegacyEntry> get entries => List.unmodifiable(_entries);
}
