import 'package:flutter/material.dart';

import '../human/two_minute_rescue_screen.dart';
import '../quests/quest_models.dart';
import '../quests/quest_store.dart';
import '../vault/memory_vault_store.dart';
import '../vault/vault_session.dart';
import 'coach_models.dart';
import 'coach_store.dart';

class CoachTimelineScreen extends StatefulWidget {
  const CoachTimelineScreen({super.key});

  @override
  State<CoachTimelineScreen> createState() => _CoachTimelineScreenState();
}

class _CoachTimelineScreenState extends State<CoachTimelineScreen> {
  CoachSourceType? _filter;

  @override
  Widget build(BuildContext context) {
    final notes = CoachStore.instance.notes.value;
    final filtered = _filter == null
        ? notes
        : notes.where((n) => n.source == _filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach Timeline'),
        actions: [
          PopupMenuButton<CoachSourceType?>(
            initialValue: _filter,
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: null, child: Text('All')),
              PopupMenuItem(
                  value: CoachSourceType.weeklyReview,
                  child: Text('Weekly Review')),
              PopupMenuItem(
                  value: CoachSourceType.questDone, child: Text('Quest Done')),
              PopupMenuItem(
                  value: CoachSourceType.moodCheckin,
                  child: Text('Mood Check‑In')),
              PopupMenuItem(
                  value: CoachSourceType.rescue,
                  child: Text('Two‑Minute Rescue')),
            ],
          ),
        ],
      ),
      body: filtered.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nothing here yet.\n\nDo a Mood Check‑In, finish a Quest, or run a Two‑Minute Rescue — then I’ll leave you breadcrumbs.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final n = filtered[filtered.length - 1 - i];
                return _NoteCard(note: n);
              },
            ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final CoachNote note;
  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(note.title),
              subtitle: Text(note.body),
              trailing: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await CoachStore.instance.delete(note.id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Deleted.')));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in note.tags.take(6)) Chip(label: Text(t)),
                  if (note.tags.length > 6) const Chip(label: Text('…')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Make a quest'),
                    onPressed: () async {
                      final title = (note.title.trim().isEmpty
                          ? 'Coach Action'
                          : note.title.trim());
                      final quest = Quest(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        title: title,
                        details: note.body.trim(),
                        createdAt: DateTime.now(),
                      );
                      await QuestStore.instance
                          .addQuest(title: quest.title, details: quest.details);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Quest created.')));
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Save to vault'),
                    onPressed: () async {
                      final ok = await VaultSession.ensureUnlocked(context);
                      if (!ok) return;
                      final pin = VaultSession.sessionPin;
                      if (pin == null) return;
                      await MemoryVaultStore.instance.add(
                        pin: pin,
                        title: note.title,
                        body: note.body,
                        tags: [...note.tags, note.source.name, 'coach'],
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Saved in vault.')));
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('2‑minute rescue'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const TwoMinuteRescueScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
