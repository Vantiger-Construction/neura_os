import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/weekly_snapshot_service.dart';
import '../services/weekly_snapshot_export_service.dart';
import '../models/weekly_snapshot_entry.dart';

class WeeklySnapshotScreen extends StatefulWidget {
  const WeeklySnapshotScreen({super.key});

  @override
  State<WeeklySnapshotScreen> createState() => _WeeklySnapshotScreenState();
}

class _WeeklySnapshotScreenState extends State<WeeklySnapshotScreen> {
  static const _trendDays = 14;

  final _service = WeeklySnapshotService.instance;
  final _exportService = WeeklySnapshotExportService.instance;
  bool _loading = true;
  bool _exporting = false;
  List<WeeklySnapshotEntry> _entries = [];
  List<WeeklySnapshotEntry> _trendEntries = [];
  String _summary = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.last7Days();
    final trendEntries = await _service.lastNDays(_trendDays);
    final summary = await _service.buildWeeklySummaryText();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _trendEntries = trendEntries;
      _summary = summary;
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
        FlSpot(i.toDouble(), _trendEntries[i].moodScore),
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
