import 'package:flutter/material.dart';

import 'human_prefs.dart';
import 'human_prefs_controller.dart';

class PersonaLabScreen extends StatelessWidget {
  const PersonaLabScreen({super.key});

  Future<void> _addItem(
    BuildContext context, {
    required String title,
    required List<String> current,
    required ValueChanged<List<String>> onChanged,
  }) async {
    final c = TextEditingController();
    final String? next;
    try {
      next = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Type and hit Add'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Add')),
          ],
        ),
      );
    } finally {
      c.dispose();
    }
    if (next == null || next.trim().isEmpty) return;
    final updated = [...current, next.trim()];
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HumanPrefs>(
      valueListenable: HumanPrefsController.instance.prefs,
      builder: (context, prefs, _) {
        final p = prefs.persona;
        return Scaffold(
          appBar: AppBar(title: const Text('Goals & Values')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'What you want more of, and what you refuse to betray. '
                'Nothing here leaves your device.\n'
                'Looking to tune how Neura talks? That moved to '
                "Settings → Neura's Personas.",
              ),
              const SizedBox(height: 16),
              _ChipsSection(
                title: 'Goals (what you want more of)',
                chips: p.goals,
                onAdd: () => _addItem(
                  context,
                  title: 'Add a goal',
                  current: p.goals,
                  onChanged: (list) => HumanPrefsController.instance.update(
                    prefs.copyWith(persona: p.copyWith(goals: list)),
                  ),
                ),
                onDelete: (i) {
                  final list = [...p.goals]..removeAt(i);
                  HumanPrefsController.instance.update(prefs.copyWith(persona: p.copyWith(goals: list)));
                },
              ),
              const SizedBox(height: 12),
              _ChipsSection(
                title: 'Values (what you refuse to betray)',
                chips: p.values,
                onAdd: () => _addItem(
                  context,
                  title: 'Add a value',
                  current: p.values,
                  onChanged: (list) => HumanPrefsController.instance.update(
                    prefs.copyWith(persona: p.copyWith(values: list)),
                  ),
                ),
                onDelete: (i) {
                  final list = [...p.values]..removeAt(i);
                  HumanPrefsController.instance.update(prefs.copyWith(persona: p.copyWith(values: list)));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChipsSection extends StatelessWidget {
  final String title;
  final List<String> chips;
  final VoidCallback onAdd;
  final ValueChanged<int> onDelete;

  const _ChipsSection({
    required this.title,
    required this.chips,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(onPressed: onAdd, icon: const Icon(Icons.add_circle_outline)),
              ],
            ),
            const SizedBox(height: 8),
            if (chips.isEmpty)
              Text('Add one…', style: Theme.of(context).textTheme.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < chips.length; i++)
                    InputChip(
                      label: Text(chips[i]),
                      onDeleted: () => onDelete(i),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
