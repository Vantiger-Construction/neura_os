import 'package:flutter/material.dart';

import '../services/dream_theme_service.dart';
import '../models/dream_entry.dart';

class DreamShow2Screen extends StatefulWidget {
  const DreamShow2Screen({super.key});

  @override
  State<DreamShow2Screen> createState() => _DreamShow2ScreenState();
}

class _DreamShow2ScreenState extends State<DreamShow2Screen> {
  final _service = DreamThemeService.instance;
  bool _loading = true;
  List<DreamEntry> _entries = [];
  Map<String, int> _themeCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _service.load();
    final entries = _service.entries;
    final counts = await _service.themeCounts();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _themeCounts = counts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sortedThemes = _themeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dream Show 2.0'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  const Text(
                    'Recurring Themes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (sortedThemes.isEmpty)
                    const Text(
                      'No dreams logged yet. When you log dreams, Neura will help you notice recurring themes over time.',
                      style: TextStyle(fontSize: 13),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: sortedThemes.map((e) {
                        final label = e.key.replaceAll('_', ' ');
                        return Chip(
                          label: Text('$label (${e.value})'),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Dream Log',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_entries.isEmpty)
                    const Text(
                      'No dreams logged yet. After you sleep, you can write about any dreams you remember and Neura will gently look for patterns.',
                      style: TextStyle(fontSize: 13),
                    )
                  else
                    ..._entries.reversed.map((d) {
                      final dateStr =
                          '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}';
                      return Card(
                        child: ListTile(
                          title: Text(dateStr),
                          subtitle: Text(
                            d.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: d.themes.isEmpty
                              ? null
                              : Wrap(
                                  spacing: 4,
                                  children: d.themes
                                      .map((t) => Chip(
                                            label: Text(t.replaceAll('_', ' ')),
                                            visualDensity: VisualDensity.compact,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                          ))
                                      .toList(),
                                ),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  const Text(
                    'Note: This feature is for reflection only and does not interpret your dreams '
                    'in a medical or diagnostic way. If your dreams leave you feeling very distressed '
                    'or unsafe, consider reaching out to a mental health professional.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
    );
  }
}
