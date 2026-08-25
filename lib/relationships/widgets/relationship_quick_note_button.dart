import 'package:flutter/material.dart';

import '../models/interaction_record.dart';
import '../services/interaction_service.dart';

/// Floating Action Button to quickly log a note/interaction for a person/client.
class RelationshipQuickNoteButton extends StatelessWidget {
  final String profileId;

  const RelationshipQuickNoteButton({super.key, required this.profileId});

  Future<void> _showNoteDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log quick note'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'What just happened?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    await InteractionService.instance.logInteraction(
      profileId: profileId,
      channel: InteractionChannel.note,
      contextSnippet: result,
      yourMood: 0,
      theirMood: 0,
      summary: result,
      nextStep: '',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note saved to this relationship.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showNoteDialog(context),
      icon: const Icon(Icons.note_add_outlined),
      label: const Text('Log note'),
    );
  }
}
