import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dreams/models/dream_entry.dart';
import '../dreams/services/dream_theme_service.dart';

/// Icons & colours mapped to detected dream themes.
const _themeVisuals = <String, ({IconData icon, Color color})>{
  'flying': (icon: Icons.flight, color: Color(0xFF81D4FA)),
  'falling': (icon: Icons.arrow_downward, color: Color(0xFFEF9A9A)),
  'being_chased': (icon: Icons.directions_run, color: Color(0xFFFFCC80)),
  'water': (icon: Icons.water_drop, color: Color(0xFF80DEEA)),
  'school': (icon: Icons.school, color: Color(0xFFA5D6A7)),
  'teeth': (icon: Icons.sentiment_very_dissatisfied, color: Color(0xFFCE93D8)),
  'lost': (icon: Icons.explore_off, color: Color(0xFFB0BEC5)),
  'family': (icon: Icons.family_restroom, color: Color(0xFFF48FB1)),
  'work': (icon: Icons.work, color: Color(0xFFFFD54F)),
  'home': (icon: Icons.home, color: Color(0xFFA5D6A7)),
  'other': (icon: Icons.nights_stay, color: Color(0xFF90CAF9)),
};

({IconData icon, Color color}) _visualFor(String theme) =>
    _themeVisuals[theme] ??
    (icon: Icons.nights_stay, color: const Color(0xFF90CAF9));

class MonthlyDreamShowScreen extends StatefulWidget {
  const MonthlyDreamShowScreen({super.key});

  @override
  State<MonthlyDreamShowScreen> createState() => _MonthlyDreamShowScreenState();
}

class _MonthlyDreamShowScreenState extends State<MonthlyDreamShowScreen>
    with TickerProviderStateMixin {
  final _themeService = DreamThemeService.instance;

  bool _loading = true;
  List<DreamEntry> _monthDreams = [];
  Map<String, int> _themeCounts = {};

  late final PageController _pageCtrl;
  late final AnimationController _autoPlay;
  Timer? _autoTimer;
  int _currentPage = 0;
  bool _isPlaying = true;

  // Fade controller per page transition
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );
    _autoPlay = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    await _themeService.load();
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month);
    final entries = _themeService.entries
        .where((e) => e.date.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final counts = await _themeService.themeCounts();

    if (!mounted) return;
    setState(() {
      _monthDreams = entries;
      _themeCounts = counts;
      _loading = false;
    });

    if (_monthDreams.isNotEmpty) {
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _monthDreams.isEmpty) return;
      _advancePage();
    });
    setState(() => _isPlaying = true);
  }

  void _stopAutoPlay() {
    _autoTimer?.cancel();
    _autoTimer = null;
    setState(() => _isPlaying = false);
  }

  Future<void> _advancePage() async {
    final next = (_currentPage + 1) % (_monthDreams.length + 1);
    // +1 for the summary card at the end
    await _fade.reverse();
    if (!mounted) return;
    _pageCtrl.jumpToPage(next);
    setState(() => _currentPage = next);
    _fade.forward();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _autoPlay.dispose();
    _fade.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Dream Show'),
        actions: [
          if (_monthDreams.isNotEmpty)
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: _isPlaying ? _stopAutoPlay : _startAutoPlay,
              tooltip: _isPlaying ? 'Pause' : 'Play',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _monthDreams.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.nights_stay,
                            size: 64, color: theme.colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'No dreams recorded this month yet.\n'
                          'Start journaling to build your dream show!',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // ── Progress dots ─────────────────────────────────
                    _buildProgressBar(),
                    // ── Animated pages ────────────────────────────────
                    Expanded(
                      child: FadeTransition(
                        opacity: _fade,
                        child: PageView.builder(
                          controller: _pageCtrl,
                          itemCount: _monthDreams.length + 1,
                          onPageChanged: (i) {
                            setState(() => _currentPage = i);
                          },
                          itemBuilder: (ctx, i) {
                            if (i < _monthDreams.length) {
                              return _DreamSceneCard(
                                dream: _monthDreams[i],
                                index: i,
                                total: _monthDreams.length,
                              );
                            }
                            return _ThemeSummaryCard(
                                counts: _themeCounts,
                                totalDreams: _monthDreams.length);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildProgressBar() {
    final total = _monthDreams.length + 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(total, (i) {
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: i <= _currentPage
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Individual dream scene card ──────────────────────────────────────────────

class _DreamSceneCard extends StatelessWidget {
  final DreamEntry dream;
  final int index;
  final int total;

  const _DreamSceneCard({
    required this.dream,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final primaryTheme = dream.themes.isNotEmpty ? dream.themes.first : 'other';
    final vis = _visualFor(primaryTheme);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                vis.color.withValues(alpha: 0.15),
                vis.color.withValues(alpha: 0.05),
              ],
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  _PulsingIcon(icon: vis.icon, color: vis.color, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Dream ${index + 1} of $total',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: vis.color),
                    ),
                  ),
                  Text(
                    _formatDate(dream.date),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Theme chips
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: dream.themes.map((t) {
                  final v = _visualFor(t);
                  return Chip(
                    avatar: Icon(v.icon, size: 16, color: v.color),
                    label: Text(t.replaceAll('_', ' ')),
                    backgroundColor: v.color.withValues(alpha: 0.12),
                    side: BorderSide.none,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Dream text
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    dream.text,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(height: 1.6, fontStyle: FontStyle.italic),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';
}

// ── Theme summary card (final slide) ────────────────────────────────────────

class _ThemeSummaryCard extends StatelessWidget {
  final Map<String, int> counts;
  final int totalDreams;

  const _ThemeSummaryCard({required this.counts, required this.totalDreams});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = sorted.isEmpty ? 1 : sorted.first.value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome,
                      color: theme.colorScheme.primary, size: 32),
                  const SizedBox(width: 12),
                  Text("This Month's Themes",
                      style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text('$totalDreams dream${totalDreams == 1 ? '' : 's'} recorded',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final entry = sorted[i];
                    final vis = _visualFor(entry.key);
                    final pct = entry.value / maxCount;
                    return Row(
                      children: [
                        Icon(vis.icon, color: vis.color, size: 24),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: Text(entry.key.replaceAll('_', ' '),
                              style: theme.textTheme.bodyMedium),
                        ),
                        Expanded(
                          child: _AnimatedBar(fraction: pct, color: vis.color),
                        ),
                        const SizedBox(width: 8),
                        Text('${entry.value}',
                            style: theme.textTheme.bodySmall),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animated theme bar ──────────────────────────────────────────────────────

class _AnimatedBar extends StatefulWidget {
  final double fraction;
  final Color color;

  const _AnimatedBar({required this.fraction, required this.color});

  @override
  State<_AnimatedBar> createState() => _AnimatedBarState();
}

class _AnimatedBarState extends State<_AnimatedBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final w = Curves.easeOutCubic.transform(_ctrl.value) * widget.fraction;
        return FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: w.clamp(0.0, 1.0),
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

// ── Pulsing theme icon ──────────────────────────────────────────────────────

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _PulsingIcon(
      {required this.icon, required this.color, required this.size});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final scale = 1.0 + 0.15 * math.sin(_ctrl.value * math.pi);
        return Transform.scale(scale: scale, child: child);
      },
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}
