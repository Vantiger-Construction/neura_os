import 'dart:math' as math;

import 'package:flutter/material.dart';

class GoodwillStreakBadge extends StatefulWidget {
  final int streak;
  final bool compact;

  const GoodwillStreakBadge({super.key, required this.streak, this.compact = false});

  @override
  State<GoodwillStreakBadge> createState() => _GoodwillStreakBadgeState();
}

class _GoodwillStreakBadgeState extends State<GoodwillStreakBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.streak > 0;

    final label = widget.compact ? '${widget.streak}🔥' : 'Goodwill Streak: ${widget.streak}';

    return AnimatedBuilder(
      animation: _pulse,
      builder: (ctx, _) {
        final t = active ? _pulse.value : 0.0;
        final glow = 4.0 + (active ? 10.0 * t : 0.0);
        final scale = 1.0 + (active ? 0.05 * t : 0.0);

        return Transform.scale(
          scale: scale,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Container(
              key: ValueKey<int>(widget.streak),
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 12, vertical: widget.compact ? 4 : 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: active ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: active ? Colors.white24 : Colors.white12),
                boxShadow: active
                    ? [
                        BoxShadow(
                          blurRadius: glow,
                          spreadRadius: 0.5,
                          color: Colors.white.withValues(alpha: 0.10 + 0.12 * t),
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(active ? Icons.volunteer_activism : Icons.volunteer_activism_outlined, size: widget.compact ? 16 : 18),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showGoodwillCelebrationDialog(BuildContext context, {required int newStreak}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return _GoodwillCelebrationDialog(streak: newStreak);
    },
  );
}

class _GoodwillCelebrationDialog extends StatefulWidget {
  final int streak;
  const _GoodwillCelebrationDialog({required this.streak});

  @override
  State<_GoodwillCelebrationDialog> createState() => _GoodwillCelebrationDialogState();
}

class _GoodwillCelebrationDialogState extends State<_GoodwillCelebrationDialog> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();
  }

  @override
  void dispose() {
    _spin.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final pop = CurvedAnimation(parent: _pop, curve: Curves.elasticOut);

    return AlertDialog(
      title: const Text('Nice. Really nice.'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: pop,
            child: RotationTransition(
              turns: _spin,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Center(
                  child: Text('✨', style: TextStyle(fontSize: 34)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Goodwill streak is now ${widget.streak} day${widget.streak == 1 ? '' : 's'}.',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Small actions count. The universe keeps receipts.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          _SparkleRow(seed: widget.streak * 37 + 9),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _SparkleRow extends StatelessWidget {
  final int seed;
  const _SparkleRow({required this.seed});

  @override
  Widget build(BuildContext context) {
    final r = math.Random(seed);
    final glyphs = const ['✨', '⭐', '💫', '🌟'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final g = glyphs[r.nextInt(glyphs.length)];
        final size = 14.0 + r.nextInt(16);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(g, style: TextStyle(fontSize: size.toDouble())),
        );
      }),
    );
  }
}
