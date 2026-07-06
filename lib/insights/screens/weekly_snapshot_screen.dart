import 'package:flutter/material.dart';

import '../services/weekly_snapshot_service.dart';
import '../models/weekly_snapshot_entry.dart';

class WeeklySnapshotScreen extends StatefulWidget {
  const WeeklySnapshotScreen({super.key});

  @override
  State<WeeklySnapshotScreen> createState() => _WeeklySnapshotScreenState();
}

class _WeeklySnapshotScreenState extends State<WeeklySnapshotScreen> {
  final _service = WeeklySnapshotService.instance;
  bool _loading = true;
  List<WeeklySnapshotEntry> _entries = [];
  String _summary = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.last7Days();
    final summary = await _service.buildWeeklySummaryText();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _summary = summary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Life Snapshot'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(
                        _summary,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "This Week's Check-ins",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_entries.isEmpty)
                    const Text(
                      'No check-ins yet. Checking in once is infinitely more than zero.',
                      style: TextStyle(fontSize: 13),
                    )
                  else
                    ..._entries.map((e) {
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              e.moodScore.toStringAsFixed(0),
                            ),
                          ),
                          title: Text(
                              '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}'),
                          subtitle: Text(
                            'Mood: ${e.moodScore.toStringAsFixed(1)}/10 · '
                            'Storms: ${e.stormsCount} · '
                            'Rituals: ${e.ritualsCompleted} · '
                            'Care: ${e.usedCareMode ? 'yes' : 'no'}',
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
