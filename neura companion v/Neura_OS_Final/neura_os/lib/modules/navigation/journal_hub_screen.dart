import 'package:flutter/material.dart';

import '../../screens/journal_prompt_screen.dart';

class JournalHubScreen extends StatelessWidget {
  const JournalHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('Get a prompt'),
              subtitle: const Text('Mood + time aware prompt (local stub for now).'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JournalPromptScreen())),
            ),
          ),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.mic_none),
              title: Text('Voice journal'),
              subtitle: Text('Coming soon: STT + tone analysis + summaries.'),
            ),
          ),
        ],
      ),
    );
  }
}
