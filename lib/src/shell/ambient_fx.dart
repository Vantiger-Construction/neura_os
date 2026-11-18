import 'dart:math';

import 'package:flutter/material.dart';

/// Lightweight ambient background FX.
///
/// - No dependencies
/// - Runs behind the entire app
/// - Off by toggle in Settings
///
/// Painted once, not animated. This layer sits under the Navigator, and every
/// route paints an opaque background over it, so a 60Hz full-screen repaint
/// here was never visible but kept the raster thread busy the whole time the
/// app was open.
class AmbientFx extends StatelessWidget {
  final bool enabled;
  const AmbientFx({super.key, required this.enabled});

  static final List<_Orb> _orbs = _seedOrbs();

  static List<_Orb> _seedOrbs() {
    final r = Random(7);
    return List.generate(9, (i) {
      return _Orb(
        x: r.nextDouble(),
        y: r.nextDouble(),
        radius: 40 + r.nextDouble() * 120,
        speed: 0.15 + r.nextDouble() * 0.45,
        phase: r.nextDouble() * pi * 2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientPainter(t: 0, orbs: _orbs),
          child: const SizedBox.expand(),
        ),
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

  _Orb(
      {required this.x,
      required this.y,
      required this.radius,
      required this.speed,
      required this.phase});

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
      final dx =
          (o.x * size.width) + sin((t * 2 * pi * o.speed) + o.phase) * 60;
      final dy =
          (o.y * size.height) + cos((t * 2 * pi * o.speed) + o.phase) * 60;

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
