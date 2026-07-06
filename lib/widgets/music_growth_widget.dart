import 'package:flutter/material.dart';

/// Visualises musical learning progress across a set of skill areas.
///
/// Pass [skills] as a map of label → progress value (0.0–1.0).
/// Defaults to a sample set when no data is provided.
class MusicGrowthWidget extends StatefulWidget {
  final Map<String, double>? skills;
  final String title;

  const MusicGrowthWidget({
    super.key,
    this.skills,
    this.title = 'Music Growth',
  });

  @override
  State<MusicGrowthWidget> createState() => _MusicGrowthWidgetState();
}

class _MusicGrowthWidgetState extends State<MusicGrowthWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  static const _defaultSkills = <String, double>{
    'Rhythm': 0.72,
    'Melody': 0.55,
    'Harmony': 0.38,
    'Theory': 0.44,
    'Ear Training': 0.61,
  };

  Map<String, double> get _skills => widget.skills ?? _defaultSkills;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.music_note_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Text(widget.title, style: tt.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _animation,
              builder: (ctx, _) => Column(
                children: _skills.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.key, style: tt.bodySmall),
                            Text(
                              '%',
                              style: tt.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: entry.value * _animation.value,
                            minHeight: 10,
                            backgroundColor: cs.outlineVariant,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(cs.primary),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Keep practising — every session counts.',
                style:
                    tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
