import 'package:flutter/material.dart';

import '../models/content_item.dart';

class NeuraCreatorScreen extends StatelessWidget {
  final NeuraContentItem item;
  final void Function(String outcome)? onOutcome;

  const NeuraCreatorScreen({
    super.key,
    required this.item,
    this.onOutcome,
  });

  IconData _iconFor(NeuraContentType type) {
    switch (type) {
      case NeuraContentType.ritual:
        return Icons.auto_awesome;
      case NeuraContentType.miniLesson:
        return Icons.school;
      case NeuraContentType.reflectionPrompt:
        return Icons.self_improvement;
      case NeuraContentType.microQuest:
        return Icons.flag;
      case NeuraContentType.joyMoment:
        return Icons.celebration;
    }
  }

  String _labelFor(NeuraContentType type) {
    switch (type) {
      case NeuraContentType.ritual:
        return 'Ritual';
      case NeuraContentType.miniLesson:
        return 'Mini Lesson';
      case NeuraContentType.reflectionPrompt:
        return 'Reflection';
      case NeuraContentType.microQuest:
        return 'Micro Quest';
      case NeuraContentType.joyMoment:
        return 'Joy Moment';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_labelFor(item.type)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(item.type), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(item.body, style: theme.textTheme.bodyLarge),
            const Spacer(),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in item.actions)
                  FilledButton(
                    onPressed: () {
                      final normalized = a.toLowerCase();
                      onOutcome?.call(normalized);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Logged: $a')),
                      );
                    },
                    child: Text(a),
                  ),
                OutlinedButton(
                  onPressed: () {
                    onOutcome?.call('dismissed');
                    Navigator.pop(context);
                  },
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
