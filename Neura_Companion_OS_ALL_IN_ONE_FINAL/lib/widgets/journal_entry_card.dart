import 'package:flutter/material.dart';
import '../models/journal_entry.dart';

class JournalEntryCard extends StatelessWidget {
  final JournalEntry entry;

  const JournalEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(entry.content),
        subtitle: Text('${entry.timestamp.toLocal()} • Mood: ${entry.moodTag}'),
      ),
    );
  }
}
