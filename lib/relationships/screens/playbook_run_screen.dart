
import 'package:flutter/material.dart';
import '../models/situation_playbook.dart';

class PlaybookRunScreen extends StatelessWidget {
  final SituationPlaybook playbook;

  const PlaybookRunScreen({super.key, required this.playbook});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playbook.name)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: playbook.steps.length,
        itemBuilder: (context, index) {
          final step = playbook.steps[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(step),
            ),
          );
        },
      ),
    );
  }
}
