import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../../modules/review/weekly_review_models.dart';
import '../../modules/review/weekly_review_screen.dart';
import '../../modules/review/weekly_review_store.dart';
import '../../weekly/widgets/weekly_life_snapshot_card.dart';
import '../services/weekly_snapshot_export_service.dart';
import '../widgets/weekly_narrative_card.dart';

/// The single, consolidated "Weekly Snapshot" screen. Combines:
///  - storms/dreams/vibe summary ([WeeklyLifeSnapshotCard], from lib/weekly)
///  - mood average/min/max, kindness acts, quests done ([WeeklyReviewStore])
///  - a real mood trend chart + recent check-ins, both from [MoodStore]
///  - CSV/PDF export + share of all of the above
class WeeklySnapshotScreen extends StatefulWidget {
  const WeeklySnapshotScreen({super.key});

  @override
  State<WeeklySnapshotScreen> createState() => _WeeklySnapshotScreenState();
}

class _WeeklySnapshotScreenState extends State<WeeklySnapshotScreen> {
  static const _trendDays = 14;

  final _exportService = WeeklySnapshotExportService.instance;
  bool _loading = true;
  bool _exporting = false;
  WeeklyReview? _review;
  List<MoodEntry> _trendEntries = [];
  List<MoodEntry> _recentEntries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final review = await WeeklyReviewStore.instance.generate();
    final moods = await MoodStore.instance.getAll();
    final now = DateTime.now();
    final trendCutoff = now.subtract(const Duration(days: _trendDays - 1));
    final recentCutoff = now.subtract(const Duration(days: 6));

    final trend = moods.where((m) => !m.timestamp.isBefore(trendCutoff)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final recent = moods.where((m) => !m.timestamp.isBefore(recentCutoff)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (!mounted) return;
    setState(() {
      _review = review;
      _trendEntries = trend;
      _recentEntries = recent;
      _loading = false;
    });
  }

  Future<void> _exportAndShare({required bool asPdf}) async {
    setState(() => _exporting = true);
    try {
      final path = asPdf
          ? await _exportService.exportPdf()
          : await _exportService.exportCsv();
      await _exportService.shareFiles([path]);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _trendChart() {
    if (_trendEntries.length < 2) {
      return const SizedBox.shrink();
    }
    final spots = [
      for (var i = 0; i < _trendEntries.length; i++)
        FlSpot(i.toDouble(), _trendEntries[i].mood0to10.toDouble()),
    ];
    return AspectRatio(
      aspectRatio: 1.8,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 10,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: const FlTitlesData(
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          ],
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _numbersCard(WeeklyReview review) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "This Week's Numbers",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (review.moodSamples == 0)
              const Text(
                'No mood check-ins yet this week.',
                style: TextStyle(fontSize: 13),
              )
            else
              Text(
                'Mood: avg ${review.moodAvg}/10 (min ${review.moodMin}, max ${review.moodMax}) '
                'across ${review.moodSamples} check-in(s)',
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 4),
            Text(
              'Kindness acts: ${review.kindnessActs} · Quests done: ${review.questDone}',
              style: const TextStyle(fontSize: 13),
            ),
            if (review.topLearned.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Helping most: ${review.topLearned.join(', ')}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const WeeklyReviewScreen()),
                      ),
                      icon: const Icon(Icons.history_outlined),
                      label: const Text('View history & notes →'),
                    ),
                  ),
                  const WeeklyLifeSnapshotCard(),
                  const SizedBox(height: 16),
                  const WeeklyNarrativeCard(),
                  const SizedBox(height: 16),
                  if (review != null) _numbersCard(review),
                  if (_trendEntries.length >= 2) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Mood Trend (last $_trendDays days)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _trendChart(),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _exporting ? null : () => _exportAndShare(asPdf: false),
                        icon: const Icon(Icons.table_view),
                        label: const Text('Export CSV'),
                      ),
                      FilledButton.icon(
                        onPressed:
                            _exporting ? null : () => _exportAndShare(asPdf: true),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Export & Share PDF'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Recent Check-ins',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_recentEntries.isEmpty)
                    const Text(
                      'No check-ins yet. Checking in once is infinitely more than zero.',
                      style: TextStyle(fontSize: 13),
                    )
                  else
                    ..._recentEntries.map((e) {
                      final d = e.timestamp;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${e.mood0to10}'),
                          ),
                          title: Text(
                              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
                              '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'),
                          subtitle: e.note.isEmpty
                              ? null
                              : Text(e.note),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
