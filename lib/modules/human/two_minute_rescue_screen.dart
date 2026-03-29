import 'dart:async';

import 'package:flutter/material.dart';

import '../mood/mood_models.dart';
import '../mood/mood_store.dart';
import '../coach/coach_hooks.dart';
import 'human_prefs_controller.dart';
import 'learning_store.dart';

class TwoMinuteRescueScreen extends StatefulWidget {
  const TwoMinuteRescueScreen({super.key});

  @override
  State<TwoMinuteRescueScreen> createState() => _TwoMinuteRescueScreenState();
}

class _TwoMinuteRescueScreenState extends State<TwoMinuteRescueScreen> {
  static const int _totalSeconds = 120;

  Timer? _timer;
  int _remaining = _totalSeconds;
  MoodEntry? _latest;
  bool _completedCoachFired = false;


  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await MoodStore.instance.latest();
    if (!mounted) return;
    setState(() => _latest = m);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _completedCoachFired = false;
    setState(() {
      _remaining = _totalSeconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        setState(() {
          _remaining = 0;
          _timer = null;
        });
        if (!_completedCoachFired) {
          _completedCoachFired = true;
          CoachHooks.afterRescueCompleted(context, latestMood: _latest);
        }
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _timer = null;
      _remaining = _totalSeconds;
    });
  }


  Future<void> _markHelpful(String id) async {
    final allow = HumanPrefsController.instance.prefs.value.allowLearning;
    if (!allow) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local learning is off in Accessibility settings.')),
      );
      return;
    }
    await LearningStore.instance.markHelpful(id);
    if (!mounted) return;
    await CoachHooks.afterRescueHelpful(context, actionId: id, latestMood: _latest);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Noted. Your future self says thanks.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mm = _latest;
    final moodLabel = mm == null ? 'unknown' : _moodLabel(mm.mood0to10);

    final suggestions = _suggestions(mm);
    final done = _remaining == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Two‑Minute Rescue')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'When everything feels like too much, do the next tiny thing.\n'
            'Latest mood: $moodLabel',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _format(_remaining),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                  if (_timer == null)
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Reset'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (done)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('You did it.'),
                subtitle: const Text('Two minutes is enough to change the direction of a day.'),
              ),
            ),
          const SizedBox(height: 8),
          Text('Pick one micro‑action:', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final s in suggestions)
            Card(
              child: ListTile(
                leading: Icon(s.icon),
                title: Text(s.title),
                subtitle: Text(s.subtitle),
                trailing: IconButton(
                  tooltip: 'This helped me',
                  icon: const Icon(Icons.thumb_up_outlined),
                  onPressed: () => _markHelpful(s.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _format(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Suggestion {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  const _Suggestion(this.id, this.icon, this.title, this.subtitle);
}

List<_Suggestion> _suggestions(MoodEntry? latest) {
  // Default "neutral good" list.
  final base = <_Suggestion>[
    const _Suggestion('water', Icons.water_drop_outlined, 'Drink water', 'Boring. Effective. Biology wins.'),
    const _Suggestion('breath', Icons.air_outlined, 'One breathing round', 'In 4, hold 4, out 6. Repeat.'),
    const _Suggestion('sun', Icons.wb_sunny_outlined, 'Step outside', 'Two minutes of sky counts.'),
    const _Suggestion('tidy', Icons.cleaning_services_outlined, 'Reset one surface', 'Desk corner. Sink. Anything.'),
  ];

  if (latest == null) return base;

  final mood = latest.mood0to10.clamp(0, 10);
  final note = latest.note.toLowerCase();

  final anxious = note.contains('stressed') || note.contains('anx') || note.contains('overwhelm') || note.contains('panic');
  final angry = note.contains('angry') || note.contains('mad') || note.contains('furious') || note.contains('rage');
  final lowWords = note.contains('sad') || note.contains('down') || note.contains('low') || note.contains('hopeless');

  if (anxious) {
    return [
      const _Suggestion('breath', Icons.air_outlined, 'Breath reset', 'In 4, hold 4, out 6.'),
      const _Suggestion('name5', Icons.visibility_outlined, 'Name 5 things', '5 see, 4 feel, 3 hear, 2 smell, 1 taste.'),
      const _Suggestion('water', Icons.water_drop_outlined, 'Drink water', 'You are a clever swamp creature.'),
      const _Suggestion('walk2', Icons.directions_walk_outlined, '2-minute walk', 'Movement burns alarm energy.'),
    ];
  }

  if (angry) {
    return [
      const _Suggestion('write1', Icons.edit_outlined, 'Write the trigger', 'One sentence: what got violated?'),
      const _Suggestion('walk2', Icons.directions_walk_outlined, '2-minute walk', 'Let the body metabolize the spike.'),
      const _Suggestion('cold', Icons.ac_unit_outlined, 'Cold splash', 'Hands under cold water for 20 sec.'),
      const _Suggestion('breath', Icons.air_outlined, 'Breath reset', 'In 4, hold 4, out 6.'),
    ];
  }

  if (mood <= 3 || lowWords) {
    return [
      const _Suggestion('text1', Icons.message_outlined, 'Text one safe human', 'One sentence: "Got 2 minutes?"'),
      const _Suggestion('sun', Icons.wb_sunny_outlined, 'Sky + light', 'Open a window or step out.'),
      const _Suggestion('water', Icons.water_drop_outlined, 'Water', 'Your brain runs on it.'),
      const _Suggestion('music1', Icons.music_note_outlined, 'One song', 'Pick steady, not doom-spiral.'),
    ];
  }

  if (mood >= 8) {
    return [
      const _Suggestion('grat', Icons.favorite_outline, 'Gratitude ping', 'Name one thing that is working.'),
      const _Suggestion('plan1', Icons.checklist_outlined, 'One next step', 'Write the next single step for today.'),
      const _Suggestion('water', Icons.water_drop_outlined, 'Water', 'Keep the machine happy.'),
      const _Suggestion('share', Icons.ios_share_outlined, 'Share the win', 'Text someone: "Small win today."'),
    ];
  }

  return base;
}

String _moodLabel(int mood0to10) {
  final m = mood0to10.clamp(0, 10);
  if (m <= 1) return 'Rough';
  if (m <= 3) return 'Low';
  if (m <= 5) return 'Neutral';
  if (m <= 7) return 'Okay';
  if (m <= 9) return 'Good';
  return 'Excellent';
}
