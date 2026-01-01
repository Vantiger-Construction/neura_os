import 'package:flutter/material.dart';

import '../human/human_prefs_controller.dart';
import '../human/human_prefs.dart';
import 'coach_store.dart';
import 'coach_timeline_screen.dart';

class CoachSettingsScreen extends StatelessWidget {
  const CoachSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neura Coach')),
      body: ValueListenableBuilder(
        valueListenable: HumanPrefsController.instance.prefs,
        builder: (context, prefs, _) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              SwitchListTile(
                value: prefs.coachEnabled,
                onChanged: (v) => HumanPrefsController.instance.update(prefs.copyWith(coachEnabled: v)),
                secondary: const Icon(Icons.psychology_alt_outlined),
                title: const Text('Enable Coach'),
                subtitle: const Text('Let Neura generate short reflections after key moments.'),
              ),
              SwitchListTile(
                value: prefs.coachPopups,
                onChanged: prefs.coachEnabled
                    ? (v) => HumanPrefsController.instance.update(prefs.copyWith(coachPopups: v))
                    : null,
                secondary: const Icon(Icons.chat_bubble_outline),
                title: const Text('Show popups'),
                subtitle: const Text('Show the reflection immediately (also saved to Coach Timeline).'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.view_timeline_outlined),
                title: const Text('Coach Timeline'),
                subtitle: const Text('Browse your reflections and export them.'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CoachTimelineScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Clear Coach Timeline'),
                subtitle: const Text('Delete all coach notes stored on this device.'),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear Coach Timeline?'),
                      content: const Text('This permanently deletes coach notes on this device.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await CoachStore.instance.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coach Timeline cleared.')),
                      );
                    }
                  }
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Coach notes are generated locally using your Persona Lab settings.\n'
                  'They are not medical advice and don\'t replace professional care.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
