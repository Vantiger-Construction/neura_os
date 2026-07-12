import 'package:flutter/material.dart';

import '../human/two_minute_rescue_screen.dart';
import '../quests/quest_store.dart';
import '../vault/memory_vault_store.dart';
import '../vault/vault_session.dart';
import 'coach_models.dart';

class CoachPopup {
  static Future<void> show(BuildContext context, CoachNote note) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(note.title.isEmpty ? 'Neura Coach' : note.title),
          content: SingleChildScrollView(
            child: Text(
                note.body.trim().isEmpty ? '(no details)' : note.body.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // Turn this reflection into a tiny quest.
                final title = _suggestQuestTitle(note);
                if (title.isNotEmpty) {
                  await QuestStore.instance.addQuest(title: title);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Quest created.')),
                    );
                  }
                }
              },
              child: const Text('Make Quest'),
            ),
            TextButton(
              onPressed: () async {
                // Save to Vault.
                final ok = await VaultSession.ensureUnlocked(ctx);
                if (!ok) return;
                final pin = VaultSession.sessionPin;
                if (pin == null) return;
                await MemoryVaultStore.instance.add(
                  pin: pin,
                  title: note.title.isEmpty ? 'Coach Note' : note.title,
                  body: note.body,
                  tags: ['coach', note.source.name, ...note.tags],
                );
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Saved to Vault.')),
                  );
                }
              },
              child: const Text('Save to Vault'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const TwoMinuteRescueScreen()),
                );
              },
              child: const Text('Start Rescue'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  static String _suggestQuestTitle(CoachNote note) {
    final t = note.title.trim();
    if (t.isNotEmpty && t.length <= 70) return t;

    // Pull a simple first actionable line.
    final lines = note.body
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';

    // Skip the vibe line if it starts with "Neura says:".
    final first =
        lines.first.toLowerCase().startsWith('neura says:') && lines.length > 1
            ? lines[1]
            : lines.first;

    // Keep it short.
    final cut = first.length > 70 ? first.substring(0, 70) : first;
    return cut;
  }
}
