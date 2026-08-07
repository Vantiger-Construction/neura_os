import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/neura_recap_export_service.dart';
import '../services/neura_recap_service.dart';

enum _RecapRange { month, year }

class NeuraRecapScreen extends StatefulWidget {
  const NeuraRecapScreen({super.key});

  @override
  State<NeuraRecapScreen> createState() => _NeuraRecapScreenState();
}

class _NeuraRecapScreenState extends State<NeuraRecapScreen> {
  _RecapRange _range = _RecapRange.month;
  bool _loading = true;
  bool _exporting = false;
  RecapData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final from = _range == _RecapRange.month
        ? DateTime(now.year, now.month - 1, now.day)
        : DateTime(now.year - 1, now.month, now.day);
    final data = await NeuraRecapService.instance.buildRecap(from: from, to: now);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _export() async {
    final data = _data;
    if (data == null) return;
    setState(() => _exporting = true);
    try {
      final path = await NeuraRecapExportService.instance.exportPdf(data);
      await NeuraRecapExportService.instance.share(path);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _dateLabel(DateTime d) => '${d.month}/${d.day}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Recap'),
        actions: [
          IconButton(
            tooltip: 'Share as PDF',
            onPressed: (_exporting || data == null) ? null : _export,
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: _loading || data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<_RecapRange>(
                    segments: const [
                      ButtonSegment(value: _RecapRange.month, label: Text('Last month')),
                      ButtonSegment(value: _RecapRange.year, label: Text('Last year')),
                    ],
                    selected: {_range},
                    onSelectionChanged: (s) {
                      setState(() => _range = s.first);
                      _load();
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${_dateLabel(data.from)} – ${_dateLabel(data.to)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (data.moodEntries.length >= 2) _trendChart(data),
                  const SizedBox(height: 16),
                  _highlightsCard(data),
                ],
              ),
            ),
    );
  }

  Widget _trendChart(RecapData data) {
    final spots = [
      for (var i = 0; i < data.moodEntries.length; i++)
        FlSpot(i.toDouble(), data.moodEntries[i].mood0to10.toDouble()),
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

  Widget _highlightsCard(RecapData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Highlights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (data.moodAvg != null)
              Text(
                'Mood: avg ${data.moodAvg}/10 (range ${data.moodMin}–${data.moodMax}) '
                'across ${data.moodEntries.length} check-in(s)',
              )
            else
              const Text('No mood check-ins logged for this range.'),
            const SizedBox(height: 8),
            Text('Kindness acts: ${data.kindnessActsTotal}'),
            const SizedBox(height: 4),
            Text('Quests completed: ${data.questsDoneTotal}'),
            const SizedBox(height: 4),
            Text(
              'Joy Moments: ${data.joyMomentsCompleted} enjoyed'
              '${data.joyMomentsSkipped > 0 ? ', ${data.joyMomentsSkipped} skipped' : ''}',
            ),
          ],
        ),
      ),
    );
  }
}
