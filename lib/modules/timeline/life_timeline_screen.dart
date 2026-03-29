import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'life_event.dart';
import 'life_timeline_service.dart';

class LifeTimelineScreen extends StatefulWidget {
  const LifeTimelineScreen({super.key});

  @override
  State<LifeTimelineScreen> createState() => _LifeTimelineScreenState();
}

class _LifeTimelineScreenState extends State<LifeTimelineScreen> {
  final TextEditingController _search = TextEditingController();
  String _typeFilter = 'all';

  late Future<List<LifeEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = LifeTimelineService.instance.build();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export(BuildContext context, List<LifeEvent> events) async {
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/neura_life_timeline_$ts.json');
      final payload = {
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'count': events.length,
        'events': events.map((e) => e.toJson()).toList(growable: false),
      };
      await file
          .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Neura Life Timeline Export',
        text: 'Your Life Timeline export from Neura (local data).',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  List<LifeEvent> _applyFilters(List<LifeEvent> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((e) {
      if (_typeFilter != 'all' && e.type != _typeFilter) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.subtitle.toLowerCase().contains(q) ||
          e.type.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'mood':
        return Icons.favorite_border;
      case 'quest':
        return Icons.emoji_events_outlined;
      case 'kindness':
        return Icons.volunteer_activism_outlined;
      case 'review':
        return Icons.event_note_outlined;
      case 'coach':
        return Icons.psychology_alt_outlined;
      default:
        return Icons.bolt_outlined;
    }
  }

  String _niceType(String type) {
    switch (type) {
      case 'mood':
        return 'Mood';
      case 'quest':
        return 'Quest';
      case 'kindness':
        return 'Kindness';
      case 'review':
        return 'Weekly';
      case 'coach':
        return 'Coach';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LifeEvent>>(
      future: _future,
      builder: (context, snap) {
        final all = snap.data ?? const <LifeEvent>[];
        final filtered = _applyFilters(all);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Life Timeline'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => setState(
                    () => _future = LifeTimelineService.instance.build()),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Export JSON',
                onPressed:
                    filtered.isEmpty ? null : () => _export(context, filtered),
                icon: const Icon(Icons.ios_share),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search events…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('all', 'All'),
                      _chip('mood', 'Mood'),
                      _chip('quest', 'Quests'),
                      _chip('kindness', 'Kindness'),
                      _chip('review', 'Weekly'),
                      _chip('coach', 'Coach'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (snap.connectionState == ConnectionState.waiting)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (filtered.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        all.isEmpty
                            ? 'No life events yet.\n(Your future self is already proud of you.)'
                            : 'No events match that filter.\n(Neura checked the timeline. It was smug.)',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        final ts = '${e.ts.month}/${e.ts.day}/${e.ts.year}';
                        return Card(
                          child: ListTile(
                            leading: Icon(_iconFor(e.type)),
                            title: Text(e.title),
                            subtitle: Text(
                                '${_niceType(e.type)} • $ts\n${e.subtitle}'),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String type, String label) {
    final selected = _typeFilter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _typeFilter = type),
      ),
    );
  }
}
