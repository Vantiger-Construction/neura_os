import 'package:flutter/material.dart';

import '../mood/mood_store.dart';
import '../pay_it_forward/goodwill_controller.dart';
import 'learning_store.dart';

class LifeSnapshotScreen extends StatefulWidget {
  const LifeSnapshotScreen({super.key});

  @override
  State<LifeSnapshotScreen> createState() => _LifeSnapshotScreenState();
}

class _LifeSnapshotScreenState extends State<LifeSnapshotScreen> {
  double? _avg;
  int _entries = 0;
  List<MapEntry<String, int>> _top = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await MoodStore.instance.getAll();
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7));

    final last7 =
        all.where((e) => e.timestamp.isAfter(cutoff)).toList(growable: false);
    _entries = last7.length;

    if (last7.isNotEmpty) {
      final sum =
          last7.fold<double>(0.0, (acc, e) => acc + e.mood0to10.toDouble());
      _avg = sum / last7.length;
    } else {
      _avg = null;
    }

    _top = await LearningStore.instance.top(max: 5);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    GoodwillController.instance.ensureLoaded();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Life Snapshot'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last 7 days',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          label: 'Mood avg',
                          value: _avg == null ? '—' : _avg!.toStringAsFixed(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Metric(
                          label: 'Check-ins',
                          value: '$_entries',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: GoodwillController.instance.streak,
                    builder: (context, streak, _) {
                      return _Metric(
                        label: 'Goodwill streak',
                        value: '$streak day${streak == 1 ? '' : 's'}',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('What tended to help:',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_top.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('No “helpful” signals yet.'),
                subtitle: Text(
                    'In Two‑Minute Rescue, tap the thumbs-up on anything that helps.'),
              ),
            )
          else
            for (final e in _top)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.star_border),
                  title: Text(_prettyId(e.key)),
                  trailing: Text('×${e.value}'),
                ),
              ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Privacy promise'),
              subtitle: const Text(
                  'These stats are calculated on-device. Nothing is uploaded unless you explicitly add sync later.'),
            ),
          ),
        ],
      ),
    );
  }

  String _prettyId(String id) {
    switch (id) {
      case 'water':
        return 'Drink water';
      case 'breath':
        return 'Breath reset';
      case 'sun':
        return 'Step outside';
      case 'tidy':
        return 'Reset one surface';
      case 'name5':
        return 'Name 5 things';
      case 'walk2':
        return '2‑minute walk';
      case 'text1':
        return 'Text one safe human';
      case 'music1':
        return 'One song';
      case 'write1':
        return 'Write the trigger';
      case 'cold':
        return 'Cold splash';
      default:
        return id;
    }
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}
