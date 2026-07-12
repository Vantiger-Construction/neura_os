import 'package:flutter/material.dart';

import '../../widgets/neura_explain.dart';
import '../human/human_prefs_controller.dart';
import '../mood/mood_store.dart';
import '../coach/coach_models.dart';
import '../coach/coach_store.dart';
import '../coach/coach_engine.dart';
import 'quest_models.dart';
import 'quest_store.dart';

class QuestModeScreen extends StatefulWidget {
  const QuestModeScreen({super.key});

  @override
  State<QuestModeScreen> createState() => _QuestModeScreenState();
}

class _QuestModeScreenState extends State<QuestModeScreen> {
  List<Quest> _quests = const [];
  List<QuestDone> _done = const [];
  int _streak = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final store = QuestStore.instance;
    final quests = await store.getQuests();
    final done = await store.getDone();
    final streak = await store.currentStreak();
    if (!mounted) return;
    setState(() {
      _quests = quests;
      _done = done;
      _streak = streak;
      _loading = false;
    });
  }

  bool _doneToday(String questId) {
    final today = normalizeDay(DateTime.now());
    return _done.any((d) => d.questId == questId && normalizeDay(d.day) == today);
  }

Future<void> _maybeCoachQuest(Quest quest) async {
  final prefs = HumanPrefsController.instance.prefs.value;
  if (!prefs.coachEnabled) return;

  final mood = await MoodStore.instance.latest();
  final streak = await QuestStore.instance.currentStreak();
  final draft = NeuraCoachEngine.instance.forQuestDone(quest: quest, streak: streak, latestMood: mood);
  await CoachStore.instance.add(
    source: CoachSourceType.questDone,
    title: draft.title,
    body: draft.body,
    tags: draft.tags,
  );

  if (!mounted) return;
  if (prefs.coachPopups) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(draft.title),
        content: SingleChildScrollView(child: Text(draft.body)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }
}


  Future<void> _addQuestDialog() async {
    final titleC = TextEditingController();
    final detailsC = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('New Quest'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleC,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detailsC,
                decoration: const InputDecoration(labelText: 'Details (optional)', border: OutlineInputBorder()),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create')),
          ],
        );
      },
    );

    if (ok != true) {
      titleC.dispose();
      detailsC.dispose();
      return;
    }

    final title = titleC.text.trim();
    final details = detailsC.text.trim();
    titleC.dispose();
    detailsC.dispose();

    if (title.isEmpty) return;
    await QuestStore.instance.addQuest(title: title, details: details);
    await _load();
  }

  Future<void> _suggestQuest() async {
    final mood = await MoodStore.instance.latest();
    final prefs = HumanPrefsController.instance.prefs.value;
    final goals = prefs.persona.goals;

    String title;
    String details;

    if (goals.isNotEmpty) {
      final g = goals.first;
      title = 'Take one step toward "$g"';
      details = 'Make it tiny. 5–15 minutes. Done beats perfect.';
    } else {
      title = 'Do one tiny win';
      details = 'Pick the smallest action that moves life forward.';
    }

    if (mood != null && mood.mood0to10 <= 3) {
      title = 'Stabilize first (2 minutes)';
      details = 'Breathe 4–6. Drink water. One kind message to yourself.';
    }

    await QuestStore.instance.addQuest(title: title, details: details);
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quest spawned. Neura approves.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final explain = NeuraExplainSpec(
      title: 'Quest Mode',
      body: 'Quests are tiny missions designed to generate momentum without turning your life into a spreadsheet cult.',
      bullets: const [
        'Keep quests small (5–15 minutes).',
        'Mark one done per day to build a streak.',
        'Neura can suggest quests based on your goals + recent mood.',
      ],
      footer: "Not medical advice. If you're in danger or in crisis, use the Support Center or local emergency services.",
    );

    final active = _quests.where((q) => !q.archived).toList().reversed.toList();
    final archived = _quests.where((q) => q.archived).toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quest Mode'),
        actions: [
          IconButton(
            tooltip: 'Why?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showNeuraExplain(context, spec: explain),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuestDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Quest'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_fire_department_outlined),
                    title: Text('Streak: $_streak day${_streak == 1 ? '' : 's'}'),
                    subtitle: const Text('One quest done per day keeps the doomscroll away.'),
                    trailing: FilledButton.icon(
                      onPressed: _suggestQuest,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Suggest'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Active', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (active.isEmpty)
                  const Text('No active quests. Create one or tap Suggest.'),
                ...active.map((q) {
                  final doneToday = _doneToday(q.id);
                  return Card(
                    child: ListTile(
                      leading: Icon(doneToday ? Icons.check_circle : Icons.radio_button_unchecked),
                      title: Text(q.title),
                      subtitle: q.details.trim().isEmpty ? null : Text(q.details),
                      onTap: () async {
                        if (doneToday) {
                          await QuestStore.instance.unmarkDoneToday(q.id);
                        } else {
                          await QuestStore.instance.markDoneToday(q.id);
                          await _maybeCoachQuest(q);
                        }
                        await _load();
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'archive') await QuestStore.instance.toggleArchived(q.id);
                          if (v == 'delete') await QuestStore.instance.deleteQuest(q.id);
                          await _load();
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'archive', child: Text('Archive')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                if (archived.isNotEmpty) ...[
                  Text('Archived', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...archived.map((q) {
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.archive_outlined),
                        title: Text(q.title),
                        subtitle: const Text('Tap menu to unarchive or delete.'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'unarchive') await QuestStore.instance.toggleArchived(q.id);
                            if (v == 'delete') await QuestStore.instance.deleteQuest(q.id);
                            await _load();
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(value: 'unarchive', child: Text('Unarchive')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}
