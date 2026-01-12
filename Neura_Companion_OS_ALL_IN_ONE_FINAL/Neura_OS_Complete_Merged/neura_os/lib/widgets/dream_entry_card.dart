import 'package:flutter/material.dart';
import '../models/dream_entry.dart';

class DreamEntryCard extends StatelessWidget {
  final DreamEntry entry;

  const DreamEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(entry.transcript),
        subtitle: Text('${entry.timestamp.toLocal()}\n${entry.moodSummary}'),
        isThreeLine: true,
      ),
    );
  }
}
