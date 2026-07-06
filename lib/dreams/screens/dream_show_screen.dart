import 'package:flutter/material.dart';

import '../services/dream_service.dart';
import '../services/dream_theme_service.dart';
import '../models/dream_entry.dart';

// DreamThemeSummary is exported from dream_theme_service.dart

class DreamShowScreen extends StatefulWidget {
  const DreamShowScreen({super.key});

  @override
  State<DreamShowScreen> createState() => _DreamShowScreenState();
}

class _DreamShowScreenState extends State<DreamShowScreen> {
  final _dreams = DreamService.instance;
  final _themes = DreamThemeService.instance;

  bool _loading = true;
  List<DreamEntry> _entries = [];
  DreamThemeSummary? _summary;

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _tagsController = TextEditingController();
  String _mood = 'weird';
  double _vividness = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final dreams = await _dreams.loadDreams();
    final summary = await _themes.computeSummary(days: 30);
    if (!mounted) return;
    setState(() {
      _entries = dreams;
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _saveDream() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    if (title.isEmpty && desc.isEmpty) return;

    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final entry = DreamEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      title: title.isEmpty ? 'Untitled dream' : title,
      description: desc,
      tags: tags,
      vividness: _vividness.round().clamp(1, 5),
      mood: _mood,
    );

    await _dreams.addOrUpdateDream(entry);
    _titleController.clear();
    _descController.clear();
    _tagsController.clear();
    _mood = 'weird';
    _vividness = 3;

    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dream added to the show.')),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dream Show'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (summary != null) _buildSummaryCard(summary),
                const SizedBox(height: 8),
                Expanded(
                  child: _entries.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No dreams recorded yet.\n\n'
                              'When you wake up, drop a quick note here.\n'
                              'Neura will start spotting recurring themes.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : PageView.builder(
                          controller: PageController(viewportFraction: 0.9),
                          itemCount: _entries.length,
                          itemBuilder: (ctx, i) {
                            final d = _entries[i];
                            return _buildDreamEpisodeCard(d, i);
                          },
                        ),
                ),
                const Divider(height: 1),
                _buildQuickAddPanel(),
              ],
            ),
    );
  }

  Widget _buildSummaryCard(DreamThemeSummary summary) {
    return Card(
      margin: const EdgeInsets.all(12),
      color: Colors.deepPurple.shade900,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Last 30 nights',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Dreams recorded: ${summary.dreamCount}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            if (summary.topWords.isNotEmpty)
              Text(
                'Recurring symbols: ${summary.topWords.join(', ')}',
                style: const TextStyle(color: Colors.white70),
              ),
            if (summary.topTags.isNotEmpty)
              Text(
                'Themes: ${summary.topTags.join(', ')}',
                style: const TextStyle(color: Colors.white70),
              ),
            if (summary.topMood != 'unknown')
              Text(
                'Most common dream mood: ${summary.topMood}',
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDreamEpisodeCard(DreamEntry d, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Episode ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                d.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                d.description,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Chip(
                    label: Text('Mood: ${d.mood}'),
                  ),
                  Chip(
                    label: Text('Vividness: ${d.vividness}/5'),
                  ),
                  ...d.tags.map(
                    (t) => Chip(
                      label: Text('#$t'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAddPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick add dream',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
            ),
          ),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'What do you remember?',
            ),
            maxLines: 3,
          ),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              labelText: 'Tags (comma separated, e.g. falling,school)',
            ),
          ),
          Row(
            children: [
              const Text('Mood:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _mood,
                items: const [
                  DropdownMenuItem(value: 'weird', child: Text('Weird')),
                  DropdownMenuItem(value: 'scary', child: Text('Scary')),
                  DropdownMenuItem(value: 'exciting', child: Text('Exciting')),
                  DropdownMenuItem(value: 'calm', child: Text('Calm')),
                  DropdownMenuItem(value: 'sad', child: Text('Sad')),
                ],
                onChanged: (v) {
                  setState(() {
                    _mood = v ?? 'weird';
                  });
                },
              ),
              const SizedBox(width: 16),
              const Text('Vividness:'),
              Expanded(
                child: Slider(
                  value: _vividness,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: _vividness.round().toString(),
                  onChanged: (v) {
                    setState(() {
                      _vividness = v;
                    });
                  },
                ),
              ),
              ElevatedButton(
                onPressed: _saveDream,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
