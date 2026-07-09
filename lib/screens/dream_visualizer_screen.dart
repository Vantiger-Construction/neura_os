import 'package:flutter/material.dart';
import '../dreams/models/dream_entry.dart';
import '../dreams/services/dream_service.dart';

class DreamVisualizerScreen extends StatefulWidget {
  const DreamVisualizerScreen({super.key});

  @override
  State<DreamVisualizerScreen> createState() => _DreamVisualizerScreenState();
}

class _DreamVisualizerScreenState extends State<DreamVisualizerScreen> {
  List<DreamEntry> _dreams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dreams = await DreamService.instance.loadDreams();
    if (mounted) setState(() { _dreams = dreams; _loading = false; });
  }

  static String _fmtDate(DateTime d) {
    final mo = d.month.toString().padLeft(2, '0');
    final dy = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mo-$dy';
  }

  Color _moodColor(String mood, ColorScheme cs) {
    switch (mood.toLowerCase()) {
      case 'peaceful':
      case 'calm':
        return Colors.teal;
      case 'scary':
      case 'nightmare':
        return cs.error;
      case 'happy':
      case 'joyful':
        return Colors.amber;
      case 'sad':
        return Colors.blueGrey;
      case 'weird':
      default:
        return cs.secondary;
    }
  }

  IconData _moodIcon(String mood) {
    switch (mood.toLowerCase()) {
      case 'peaceful':
      case 'calm':
        return Icons.self_improvement;
      case 'scary':
      case 'nightmare':
        return Icons.warning_amber_outlined;
      case 'happy':
      case 'joyful':
        return Icons.sentiment_very_satisfied_outlined;
      case 'sad':
        return Icons.sentiment_dissatisfied_outlined;
      case 'weird':
      default:
        return Icons.auto_awesome_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Dream Visualizer')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dreams.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.nights_stay_outlined,
                          size: 64, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text('No dreams recorded yet.',
                          style:
                              tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _dreams.length,
                  itemBuilder: (ctx, i) {
                    final dream = _dreams[i];
                    final color = _moodColor(dream.mood, cs);
                    final isLast = i == _dreams.length - 1;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Timeline spine
                          SizedBox(
                            width: 32,
                            child: Column(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                if (!isLast)
                                  Expanded(
                                    child: Container(
                                      width: 2,
                                      color: cs.outlineVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Card
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Card(
                                elevation: 0,
                                color: cs.surfaceContainerLow,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                      color: color.withAlpha(100), width: 1),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(_moodIcon(dream.mood),
                                              size: 16, color: color),
                                          const SizedBox(width: 6),
                                           Text(
                                            _fmtDate(dream.date),
                                            style: tt.labelSmall
                                                ?.copyWith(color: color),
                                          ),
                                          const Spacer(),
                                          _VividnessBar(
                                              vividness: dream.vividness),
                                        ],
                                      ),
                                      if (dream.title.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(dream.title,
                                            style: tt.titleSmall),
                                      ],
                                      if (dream.description.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          dream.description.length > 120
                                              ? '${dream.description.substring(0, 120)}…'
                                              : dream.description,
                                          style: tt.bodySmall,
                                        ),
                                      ],
                                      if (dream.tags.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: dream.tags
                                              .map((t) => Chip(
                                                    label: Text(t,
                                                        style:
                                                            tt.labelSmall),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                  ))
                                              .toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class _VividnessBar extends StatelessWidget {
  final int vividness; // 1–5
  const _VividnessBar({required this.vividness});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Container(
          width: 6,
          height: 10,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < vividness ? cs.primary : cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
