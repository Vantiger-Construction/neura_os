import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/neura_explain.dart';
import '../coach/coach_models.dart';
import '../coach/coach_store.dart';
import '../coach/coach_engine.dart';
import '../human/human_prefs_controller.dart';
import 'weekly_review_models.dart';
import 'weekly_review_store.dart';

class WeeklyReviewScreen extends StatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  State<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends State<WeeklyReviewScreen> {
  bool _loading = true;
  WeeklyReview? _latest;
  List<WeeklyReview> _all = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await WeeklyReviewStore.instance.getAll();
    WeeklyReview? latest;
    if (all.isNotEmpty) latest = all.last;
    if (!mounted) return;
    setState(() {
      _all = all;
      _latest = latest;
      _loading = false;
    });
  }

  Future<void> _maybeCoachReview(WeeklyReview review) async {
    final prefs = HumanPrefsController.instance.prefs.value;
    if (!prefs.coachEnabled) return;

    final draft = NeuraCoachEngine.instance.forWeeklyReview(review: review);
    await CoachStore.instance.add(
      source: CoachSourceType.weeklyReview,
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

  Future<void> _generate() async {
    await WeeklyReviewStore.instance.generate();
    final all = await WeeklyReviewStore.instance.getAll();
    if (all.isNotEmpty) {
      await _maybeCoachReview(all.last);
    }
    await _load();
  }

  Future<void> _editNote(WeeklyReview r) async {
    final c = TextEditingController(text: r.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a note'),
        content: TextField(
          controller: c,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Wins, lessons, what to try next week…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      await WeeklyReviewStore.instance.updateNote(r.weekStart, c.text);
      await _load();
    }
    c.dispose();
  }

  Future<void> _copyJson(WeeklyReview r) async {
    final raw = jsonEncode(r.toJson());
    await Clipboard.setData(ClipboardData(text: raw));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied review JSON to clipboard.')));
    }
  }

  String _weekLabel(DateTime ws) {
    final we = ws.add(const Duration(days: 6));
    return '${ws.month}/${ws.day} – ${we.month}/${we.day}';
  }

  @override
  Widget build(BuildContext context) {
    final explain = NeuraExplainSpec(
      title: 'Weekly Review',
      body: 'This is a local-only snapshot of your last 7 days. It’s meant to be kind, not judgmental.',
      bullets: const [
        'Mood stats come from your Mood Check‑Ins.',
        'Kindness comes from Pay It Forward.',
        'Quest momentum comes from Quest Mode.',
        'Helpful actions come from your local “Learning” taps.',
      ],
      footer: 'You can export by copying JSON. This is not medical advice or diagnosis.',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Review'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: () => showNeuraExplain(context, spec: explain)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generate,
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('Generate'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_latest == null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_note_outlined),
                      title: const Text('No review yet'),
                      subtitle: const Text('Tap Generate to create your first weekly review.'),
                      trailing: FilledButton(onPressed: _generate, child: const Text('Generate')),
                    ),
                  )
                else
                  _ReviewCard(
                    title: 'Latest (${_weekLabel(_latest!.weekStart)})',
                    review: _latest!,
                    onEditNote: () => _editNote(_latest!),
                    onCopy: () => _copyJson(_latest!),
                  ),
                const SizedBox(height: 16),
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_all.isEmpty) const Text('No history yet.') else ...[
                  ..._all.reversed.map((r) {
                    return _ReviewCard(
                      title: _weekLabel(r.weekStart),
                      review: r,
                      onEditNote: () => _editNote(r),
                      onCopy: () => _copyJson(r),
                    );
                  })
                ]
              ],
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final WeeklyReview review;
  final VoidCallback onEditNote;
  final VoidCallback onCopy;

  const _ReviewCard({
    required this.title,
    required this.review,
    required this.onEditNote,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                IconButton(tooltip: 'Copy JSON', onPressed: onCopy, icon: const Icon(Icons.copy)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _chip(context, Icons.favorite_border, 'Mood avg', '${review.moodAvg}/10'),
                _chip(context, Icons.show_chart, 'Range', '${review.moodMin}–${review.moodMax}'),
                _chip(context, Icons.data_usage, 'Samples', '${review.moodSamples}'),
                _chip(context, Icons.volunteer_activism, 'Kindness', '${review.kindnessActs}'),
                _chip(context, Icons.emoji_events_outlined, 'Quests', '${review.questDone}'),
              ],
            ),
            const SizedBox(height: 10),
            if (review.topLearned.isNotEmpty)
              Text('Helpful actions: ${review.topLearned.join(', ')}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            if (review.note.trim().isNotEmpty)
              Text('Note: ${review.note}', style: theme.textTheme.bodyMedium)
            else
              Text('No note yet.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onEditNote,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Add note'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String k, String v) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$k: $v'),
    );
  }
}
