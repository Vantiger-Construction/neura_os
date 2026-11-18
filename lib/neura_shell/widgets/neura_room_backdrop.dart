import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../models/neura_room.dart';

/// Room-tinted backdrop under the whole app.
///
/// Painted once, not animated. It sits under the Navigator, and every route
/// paints an opaque background over it, so the old 60Hz drifting-spark
/// repaint was never visible but cost a full-screen repaint every frame for
/// as long as the app was open. The gradient still eases between rooms.
class NeuraRoomBackdrop extends StatelessWidget {
  final NeuraRoom room;

  const NeuraRoomBackdrop({super.key, required this.room});

  static final List<_Spark> _sparks = _SparkField.seeded(48, seed: 42);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: room.gradient,
        ),
      ),
      // Keep the sparks in their own cached layer so a room change only
      // re-records the gradient underneath.
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SparkFieldPainter(progress: 0, sparks: _sparks),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _Spark {
  final double x;
  final double y;
  final double r;
  final double speed;
  final double alpha;

  const _Spark({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.alpha,
  });
}

class _SparkField {
  static List<_Spark> seeded(int count, {required int seed}) {
    final rnd = Random(seed);
    return List.generate(count, (_) {
      return _Spark(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        r: lerpDouble(0.6, 2.2, rnd.nextDouble())!,
        speed: lerpDouble(0.03, 0.12, rnd.nextDouble())!,
        alpha: lerpDouble(0.05, 0.14, rnd.nextDouble())!,
      );
    });
  }
}

class _SparkFieldPainter extends CustomPainter {
  final double progress;
  final List<_Spark> sparks;

  _SparkFieldPainter({required this.progress, required this.sparks});

  // The vignette doesn't depend on `progress`, only on canvas size —
  // recreating its shader every frame (was happening on every repaint at
  // 60Hz) was pure waste, so cache it and only rebuild when size changes.
  static Size? _cachedSize;
  static Paint? _cachedVignette;

  Paint _vignetteFor(Size size) {
    if (_cachedSize == size && _cachedVignette != null) return _cachedVignette!;
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.45),
        ],
        stops: const [0.55, 1.0],
      ).createShader(Offset(size.width / 2, size.height / 2) & size);
    _cachedSize = size;
    _cachedVignette = vignette;
    return vignette;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final s in sparks) {
      final dy = (s.y + progress * s.speed) % 1.0;
      final p = Offset(s.x * size.width, dy * size.height);
      paint.color = Colors.white.withValues(alpha: s.alpha);
      canvas.drawCircle(p, s.r, paint);
    }

    canvas.drawRect(Offset.zero & size, _vignetteFor(size));
  }

  @override
  bool shouldRepaint(covariant _SparkFieldPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.sparks != sparks;
  }
}
