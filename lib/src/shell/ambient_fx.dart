import 'dart:math';

import 'package:flutter/material.dart';

/// Lightweight ambient background FX.
///
/// - No dependencies
/// - Runs behind the entire app
/// - Off by toggle in Settings
class AmbientFx extends StatefulWidget {
  final bool enabled;
  const AmbientFx({super.key, required this.enabled});

  @override
  State<AmbientFx> createState() => _AmbientFxState();
}

class _AmbientFxState extends State<AmbientFx> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  final Random _r = Random(7);
  late final List<_Orb> _orbs;

  @override
  void initState() {
    super.initState();
    _orbs = List.generate(9, (i) {
      return _Orb(
        x: _r.nextDouble(),
        y: _r.nextDouble(),
        radius: 40 + _r.nextDouble() * 120,
        speed: 0.15 + _r.nextDouble() * 0.45,
        phase: _r.nextDouble() * pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(
            painter: _AmbientPainter(
              t: _c.value,
              orbs: _orbs,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _Orb {
  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;

  _Orb({required this.x, required this.y, required this.radius, required this.speed, required this.phase});

  // radius never changes after construction, so the shader can be built once
  // (centered at the origin) and repositioned per frame via canvas.translate
  // instead of rebuilding a RadialGradient every repaint.
  Paint? _paint;
  Paint get paint {
    return _paint ??= Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.cyanAccent.withValues(alpha: 0.05),
          Colors.deepPurpleAccent.withValues(alpha: 0.03),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
  }
}

class _AmbientPainter extends CustomPainter {
  final double t;
  final List<_Orb> orbs;

  _AmbientPainter({required this.t, required this.orbs});

  // The vignette doesn't depend on `t`, only on canvas size — recreating its
  // shader every frame (was happening on every repaint at 60Hz) was pure
  // waste, so cache it and only rebuild when the size actually changes.
  static Size? _cachedSize;
  static Paint? _cachedBg;

  Paint _bgFor(Size size) {
    if (_cachedSize == size && _cachedBg != null) return _cachedBg!;
    final bg = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.55),
        ],
      ).createShader(Offset(size.width / 2, size.height / 2) & size);
    _cachedSize = size;
    _cachedBg = bg;
    return bg;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bgFor(size));

    for (final o in orbs) {
      final dx = (o.x * size.width) + sin((t * 2 * pi * o.speed) + o.phase) * 60;
      final dy = (o.y * size.height) + cos((t * 2 * pi * o.speed) + o.phase) * 60;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.drawCircle(Offset.zero, o.radius, o.paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.orbs != orbs;
  }
}
