import 'package:flutter/material.dart';

import 'human_prefs.dart';
import 'human_prefs_controller.dart';
import 'persona_profile.dart';

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
          appBar: AppBar(title: const Text('Persona Lab')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Tune how Neura talks to you. Nothing here leaves your device.\n'
                'Move sliders until Neura feels like a useful co-pilot instead of a motivational poster.',
              ),
              const SizedBox(height: 16),
              _SliderRow(
                label: 'Directness',
                left: 'Gentle',
                right: 'Blunt',
                value: p.directness,
                onChanged: (v) => HumanPrefsController.instance.update(
                  prefs.copyWith(persona: p.copyWith(directness: v)),
                ),
              ),
              _SliderRow(
                label: 'Humor',
                left: 'Serious',
                right: 'Jokey',
                value: p.humor,
                onChanged: (v) => HumanPrefsController.instance.update(
                  prefs.copyWith(persona: p.copyWith(humor: v)),
                ),
              ),
              _SliderRow(
                label: 'Energy',
                left: 'Calm',
                right: 'Hype',
                value: p.energy,
                onChanged: (v) => HumanPrefsController.instance.update(
                  prefs.copyWith(persona: p.copyWith(energy: v)),
                ),
              ),
              _SliderRow(
                label: 'Depth',
                left: 'Simple',
                right: 'Deep',
                value: p.depth,
                onChanged: (v) => HumanPrefsController.instance.update(
                  prefs.copyWith(persona: p.copyWith(depth: v)),
                ),
              ),
              _SliderRow(
                label: 'Pacing',
                left: 'Slow',
                right: 'Fast',
                value: p.pacing,
                onChanged: (v) => HumanPrefsController.instance.update(
                  prefs.copyWith(persona: p.copyWith(pacing: v)),
                ),
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preview', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(_preview(p)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _preview(PersonaProfile p) {
    final blunt = p.directness > 0.65;
    final jokey = p.humor > 0.65;
    final deep = p.depth > 0.65;
    final calm = p.energy < 0.35;

    final a = blunt ? 'Here\'s the deal' : 'Okay';
    final b = calm ? 'Let\'s take one slow step.' : 'We\'re moving.';
    final c = jokey ? 'No shame, just science.' : 'No shame.';
    final d = deep ? 'What belief is steering the ship right now?' : 'What\'s the next right action?';

    return '$a — $b $c $d';
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String left;
  final String right;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.left,
    required this.right,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                Expanded(child: Text(left, style: Theme.of(context).textTheme.bodySmall)),
                Expanded(child: Text(right, textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
            Slider(value: value, onChanged: onChanged),
          ],
        ),
      ),
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
