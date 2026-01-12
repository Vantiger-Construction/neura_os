import 'dart:math';

import 'package:flutter/material.dart';

import '../models/neura_room.dart';

class NeuraRoomBackdrop extends StatefulWidget {
  final NeuraRoom room;

  const NeuraRoomBackdrop({super.key, required this.room});

  @override
  State<NeuraRoomBackdrop> createState() => _NeuraRoomBackdropState();
}

class _NeuraRoomBackdropState extends State<NeuraRoomBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  late final List<_Spark> _sparks;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: const Duration(seconds: 18))
      ..repeat();
    _sparks = _SparkField.seeded(48, seed: 42);
  }

  @override
  void didUpdateWidget(covariant NeuraRoomBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the same animation + spark field; only gradient changes.
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.room.gradient;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          return CustomPaint(
            painter: _SparkFieldPainter(progress: _t.value, sparks: _sparks),
            child: const SizedBox.expand(),
          );
        },
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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final s in sparks) {
      final dy = (s.y + progress * s.speed) % 1.0;
      final p = Offset(s.x * size.width, dy * size.height);
      paint.color = Colors.white.withOpacity(s.alpha);
      canvas.drawCircle(p, s.r, paint);
    }

    // Vignette for legibility.
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withOpacity(0.45),
        ],
        stops: const [0.55, 1.0],
      ).createShader(Offset(size.width / 2, size.height / 2) & size);

    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _SparkFieldPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.sparks != sparks;
  }
}
