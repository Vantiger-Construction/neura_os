import 'package:flutter/material.dart';

import 'focus_controller.dart';
import 'focus_mode.dart';

class FocusOfficeScreen extends StatelessWidget {
  const FocusOfficeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus Office')),
      body: ValueListenableBuilder(
        valueListenable: FocusController.instance.state,
        builder: (context, state, _) {
          final accent = state.mode.accent;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(state.mode.icon, color: accent),
                  title: Text('Current: ${state.mode.label}'),
                  subtitle: Text(state.mode.subtitle),
                ),
              ),
              const SizedBox(height: 12),
              Text('Pick a mode',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: FocusMode.values.map((m) {
                  final selected = m == state.mode;
                  final c = m.accent;
                  return SizedBox(
                    width: 170,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: selected
                                ? (c ?? Theme.of(context).colorScheme.primary)
                                : Colors.white24),
                        backgroundColor: selected ? Colors.white10 : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      onPressed: () => FocusController.instance.setMode(m),
                      icon: Icon(m.icon, color: c),
                      label: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.label, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            m.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Pro tip: Focus Mode is not a productivity religion. It\'s a UI cue that helps your brain pick a lane. '
                    'You can switch anytime, guilt-free. Neura approves.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
