import 'package:flutter/material.dart';
import 'dream_journal_entry.dart';

class NeuraDreamJournalScreen extends StatelessWidget {
  final List<DreamJournalEntry> dreamEntries;

  NeuraDreamJournalScreen({required this.dreamEntries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dream Journal')),
      body: ListView.builder(
        itemCount: dreamEntries.length,
        itemBuilder: (context, index) {
          final entry = dreamEntries[index];
          return Card(
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: ListTile(
              title: Text(
                "Dream from ${entry.timestamp.toLocal().toString().split(' ')[0]}",
              ),
              subtitle: Text(
                "Mood: ${entry.emotion}\n${entry.interpretation}",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text("Dream Details"),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Date: ${entry.timestamp.toLocal()}"),
                        SizedBox(height: 10),
                        Text("Transcript: ${entry.transcript}"),
                        SizedBox(height: 10),
                        Text("Mood: ${entry.emotion}"),
                        SizedBox(height: 10),
                        Text("Interpretation: ${entry.interpretation}"),
                        SizedBox(height: 10),
                        Text("Visual Theme: ${entry.dreamscapeTheme}"),
                      ],
                    ),
                    actions: [
                      TextButton(
                        child: Text("Close"),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
