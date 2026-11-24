import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../../profiles/local_profile_service.dart';
import '../widgets/neura_mood_painting.dart';

/// A private gallery: one painting per week of mood check-ins, newest first.
/// Paintings are drawn on this device from the encrypted mood history; only
/// an image the user explicitly saves leaves the app.
class NeuraMoodGalleryScreen extends StatefulWidget {
  const NeuraMoodGalleryScreen({super.key, this.loadEntries});

  final Future<List<MoodEntry>> Function()? loadEntries;

  static const maxWeeks = 26;

  /// The weeks (Monday starts) that have check-ins, newest first.
  static List<DateTime> weeksWithEntries(List<MoodEntry> entries) {
    final weeks = {
      for (final entry in entries) NeuraMoodPainting.weekOf(entry.timestamp),
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return weeks.take(maxWeeks).toList();
  }

  @override
  State<NeuraMoodGalleryScreen> createState() => _NeuraMoodGalleryScreenState();
}

class _NeuraMoodGalleryScreenState extends State<NeuraMoodGalleryScreen> {
  List<MoodEntry>? _entries;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (LocalProfileService.instance.enabled) {
      setState(() => _entries = const []);
      return;
    }
    try {
      final load = widget.loadEntries ?? MoodStore.instance.getAll;
      final entries = await load();
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _label(BuildContext context, DateTime week) =>
      'Week of ${MaterialLocalizations.of(context).formatMediumDate(week)}';

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Mood gallery')),
      body: SafeArea(
        child: _failed
            ? const Center(child: Text('Mood history could not be read.'))
            : entries == null
                ? const Center(child: CircularProgressIndicator())
                : _grid(context, entries),
      ),
    );
  }

  Widget _grid(BuildContext context, List<MoodEntry> entries) {
    final weeks = NeuraMoodGalleryScreen.weeksWithEntries(entries);
    if (weeks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Check in with your mood and each week becomes a painting here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: weeks.length,
      itemBuilder: (context, index) {
        final week = weeks[index];
        final painting = NeuraMoodPainting(weekStart: week, entries: entries);
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => _PaintingView(
                painting: painting,
                title: _label(context, week),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CustomPaint(
                    painter: painting,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(_label(context, week),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }
}

class _PaintingView extends StatefulWidget {
  const _PaintingView({required this.painting, required this.title});

  final NeuraMoodPainting painting;
  final String title;

  @override
  State<_PaintingView> createState() => _PaintingViewState();
}

class _PaintingViewState extends State<_PaintingView> {
  final _boundary = GlobalKey();
  bool _saving = false;

  Future<void> _save() async {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || _saving) return;
    setState(() => _saving = true);
    String message;
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('No image');
      final week = widget.painting.weekStart.toIso8601String().substring(0, 10);
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save mood painting',
        fileName: 'neura-mood-week-$week.png',
        bytes: Uint8List.view(data.buffer),
      );
      message = saved == null ? 'Not saved.' : 'Painting saved.';
    } catch (_) {
      message = 'The painting could not be saved.';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final painting = widget.painting;
    final count = painting.entries.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Save image',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: RepaintBoundary(
                      key: _boundary,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CustomPaint(
                          painter: painting,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                count == 1
                    ? 'One check-in. Each stroke is a check-in: higher and '
                        'warmer for better moods, thicker with more energy, '
                        'longer after more sleep.'
                    : '$count check-ins. Each stroke is a check-in: higher '
                        'and warmer for better moods, thicker with more '
                        'energy, longer after more sleep.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
