import 'package:flutter/material.dart';

import 'therapy_models.dart';

class TherapyPromptCard extends StatelessWidget {
  final TherapyPrompt prompt;
  final VoidCallback onTap;

  const TherapyPromptCard(
      {super.key, required this.prompt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(prompt.title),
        subtitle: Text(prompt.instruction),
        trailing: const Icon(Icons.edit_note),
        onTap: onTap,
      ),
    );
  }
}
