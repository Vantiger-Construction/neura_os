import 'package:flutter/material.dart';

import '../services/weekly_snapshot_service.dart';
import '../models/weekly_summary.dart';

class WeeklyLifeSnapshotCard extends StatefulWidget {
  const WeeklyLifeSnapshotCard({super.key});

  @override
  State<WeeklyLifeSnapshotCard> createState() =>
      _WeeklyLifeSnapshotCardState();
}

class _WeeklyLifeSnapshotCardState extends State<WeeklyLifeSnapshotCard> {
  final _service = WeeklySnapshotService.instance;

  bool _loading = true;
  WeeklySummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final summary = await _service.buildSummary(days: 7);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      color: Colors.indigo.shade900,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _load,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const SizedBox(
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
              : summary == null
                  ? const Text(
                      'Neura doesn\'t have enough data yet for this week.',
                      style: TextStyle(color: Colors.white),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Weekly Life Snapshot',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _pill(
                              'Storms: ${summary.stormsCount}',
                            ),
                            _pill(
                              'Dreams: ${summary.dreamsCount}',
                            ),
                            if (summary.safetyStormsCount > 0)
                              _pill(
                                'Safety alerts: ${summary.safetyStormsCount}',
                                danger: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (summary.topStormFeeling != 'unknown')
                          Text(
                            'Most common feeling: ${summary.topStormFeeling}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        if (summary.topDreamTheme != 'unknown')
                          Text(
                            'Recurring theme: ${summary.topDreamTheme}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          summary.vibeSentence,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap to refresh this snapshot.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _pill(String text, {bool danger = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: danger ? Colors.red.shade700 : Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}
