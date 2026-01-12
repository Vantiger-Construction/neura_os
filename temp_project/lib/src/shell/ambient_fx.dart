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

class _AmbientFxState extends State<AmbientFx>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))
        ..repeat();
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

  const _Orb(
      {required this.x,
      required this.y,
      required this.radius,
      required this.speed,
      required this.phase});
}

class _AmbientPainter extends CustomPainter {
  final double t;
  final List<_Orb> orbs;

  _AmbientPainter({required this.t, required this.orbs});

  @override
  void paint(Canvas canvas, Size size) {
    // Placeholder paint method
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.orbs != orbs;
  }
}
