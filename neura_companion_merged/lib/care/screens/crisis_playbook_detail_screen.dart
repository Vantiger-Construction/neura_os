import 'package:flutter/material.dart';

import '../models/crisis_playbook.dart';

class CrisisPlaybookDetailScreen extends StatelessWidget {
  final CrisisPlaybook playbook;

  const CrisisPlaybookDetailScreen({super.key, required this.playbook});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(playbook.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              playbook.description,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: playbook.steps.length,
                itemBuilder: (ctx, i) {
                  final step = playbook.steps[i];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text('${i + 1}'),
                    ),
                    title: Text(step),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Important: This is not medical or emergency advice. '
              'If you or someone else may be in immediate danger, '
              'contact local emergency services or a crisis hotline right away.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
