import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Neura's penthouse, painted in code so it needs no image assets.
///
/// A night city skyline seen through floor-to-ceiling windows, with a
/// polished floor, a low lounge sofa and a warm lamp. The scene is static
/// (no animation ticker), so it costs nothing at idle and is safe for Safe
/// Mode and reduced-motion users.
///
/// [dim] lays the app background colour over the scene so it can sit behind
/// menus and content without hurting readability (0 = full scene,
/// 1 = fully hidden).
class NeuraPenthouseScene extends StatelessWidget {
  const NeuraPenthouseScene({
    super.key,
    this.dim = 0,
    this.dimColor,
    this.showFurniture = true,
  });

  final double dim;
  final Color? dimColor;
  final bool showFurniture;

  @override
  Widget build(BuildContext context) {
    final overlay = (dimColor ?? Theme.of(context).colorScheme.surface)
        .withValues(alpha: dim.clamp(0.0, 1.0));
    return RepaintBoundary(
      child: CustomPaint(
        painter: NeuraPenthousePainter(
          overlay: overlay,
          showFurniture: showFurniture,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class NeuraPenthousePainter extends CustomPainter {
  NeuraPenthousePainter({required this.overlay, required this.showFurniture});

  final Color overlay;
  final bool showFurniture;

  static const _skyTop = Color(0xFF070B1C);
  static const _skyMid = Color(0xFF16163A);
  static const _skyHorizon = Color(0xFF3A2350);
  static const _cityFar = Color(0xFF141631);
  static const _cityNear = Color(0xFF0B0C1F);
  static const _frame = Color(0xFF05060F);
  static const _floor = Color(0xFF0C0A16);
  static const _windowWarm = Color(0xFFFFD58A);
  static const _windowCool = Color(0xFF9FD8FF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final floorY = h * 0.78;

    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_skyTop, _skyMid, _skyHorizon],
          stops: <double>[0, 0.55, 1],
        ).createShader(Rect.fromLTWH(0, 0, w, floorY)),
    );

    // Stars and moon.
    final rnd = math.Random(7);
    final star = Paint();
    for (var i = 0; i < 70; i++) {
      star.color =
          Colors.white.withValues(alpha: 0.15 + rnd.nextDouble() * 0.5);
      canvas.drawCircle(
        Offset(rnd.nextDouble() * w, rnd.nextDouble() * floorY * 0.45),
        0.5 + rnd.nextDouble() * 0.9,
        star,
      );
    }
    final moon = Offset(w * 0.78, floorY * 0.16);
    final moonR = math.max(8.0, math.min(w, h) * 0.035);
    canvas.drawCircle(
      moon,
      moonR * 3,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFFFF3D6).withValues(alpha: 0.22),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: moon, radius: moonR * 3)),
    );
    canvas.drawCircle(moon, moonR, Paint()..color = const Color(0xFFFFF3D6));

    // Two layers of skyline with lit windows.
    _drawSkyline(canvas, w, floorY, rnd,
        baseline: floorY * 0.98,
        minH: floorY * 0.18,
        maxH: floorY * 0.42,
        color: _cityFar,
        litChance: 0.18);
    _drawSkyline(canvas, w, floorY, rnd,
        baseline: floorY,
        minH: floorY * 0.10,
        maxH: floorY * 0.30,
        color: _cityNear,
        litChance: 0.28);

    // Horizon glow from the city.
    canvas.drawRect(
      Rect.fromLTWH(0, floorY * 0.7, w, floorY * 0.3),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            const Color(0xFFB25FD6).withValues(alpha: 0.18),
          ],
        ).createShader(Rect.fromLTWH(0, floorY * 0.7, w, floorY * 0.3)),
    );

    // Floor-to-ceiling window frame.
    final frame = Paint()..color = _frame;
    final mullion = math.max(3.0, w * 0.008);
    final panes = math.max(2, (w / 260).round());
    for (var i = 0; i <= panes; i++) {
      final x = w * i / panes;
      canvas.drawRect(
        Rect.fromLTWH(x - mullion / 2, 0, mullion, floorY),
        frame,
      );
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, w, mullion * 1.6), frame);
    canvas.drawRect(
        Rect.fromLTWH(0, floorY - mullion, w, mullion * 1.4), frame);

    // Polished floor with a soft reflection of the skyline glow.
    final floorRect = Rect.fromLTWH(0, floorY, w, h - floorY);
    canvas.drawRect(
      floorRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.alphaBlend(
              const Color(0xFF6B3E8C).withValues(alpha: 0.25),
              _floor,
            ),
            _floor,
          ],
        ).createShader(floorRect),
    );

    if (showFurniture) _drawLounge(canvas, w, h, floorY);

    // Gentle vignette.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.35),
          ],
          stops: const <double>[0.6, 1],
        ).createShader(Offset.zero & size),
    );

    if (overlay.a > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = overlay);
    }
  }

  void _drawSkyline(
    Canvas canvas,
    double w,
    double floorY,
    math.Random rnd, {
    required double baseline,
    required double minH,
    required double maxH,
    required Color color,
    required double litChance,
  }) {
    final building = Paint()..color = color;
    final lit = Paint();
    var x = -rnd.nextDouble() * 20;
    while (x < w) {
      final bw = 18 + rnd.nextDouble() * 46;
      final bh = minH + rnd.nextDouble() * (maxH - minH);
      final rect = Rect.fromLTWH(x, baseline - bh, bw, bh);
      canvas.drawRect(rect, building);
      for (var wy = rect.top + 6; wy < rect.bottom - 6; wy += 9) {
        for (var wx = rect.left + 4; wx < rect.right - 5; wx += 8) {
          if (rnd.nextDouble() > litChance) continue;
          lit.color = (rnd.nextBool() ? _windowWarm : _windowCool)
              .withValues(alpha: 0.35 + rnd.nextDouble() * 0.45);
          canvas.drawRect(Rect.fromLTWH(wx, wy, 2.5, 3.5), lit);
        }
      }
      x += bw + rnd.nextDouble() * 6;
    }
  }

  void _drawLounge(Canvas canvas, double w, double h, double floorY) {
    final unit = math.min(w, h);

    // Warm lamp glow on the left.
    final lampX = w * 0.12;
    final lampTop = floorY - unit * 0.36;
    final glowCenter = Offset(lampX, lampTop + unit * 0.04);
    canvas.drawCircle(
      glowCenter,
      unit * 0.32,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFFFC27A).withValues(alpha: 0.30),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: glowCenter, radius: unit * 0.32),
        ),
    );
    final lampPaint = Paint()..color = const Color(0xFF1A1424);
    canvas.drawRect(
      Rect.fromLTWH(lampX - 1.5, lampTop + unit * 0.06, 3, floorY - lampTop),
      lampPaint,
    );
    final shade = Path()
      ..moveTo(lampX - unit * 0.05, lampTop + unit * 0.07)
      ..lineTo(lampX + unit * 0.05, lampTop + unit * 0.07)
      ..lineTo(lampX + unit * 0.03, lampTop)
      ..lineTo(lampX - unit * 0.03, lampTop)
      ..close();
    canvas.drawPath(shade, Paint()..color = const Color(0xFFFFD9A0));

    // Low lounge sofa, centred, as a soft silhouette.
    final sofaW = math.min(w * 0.7, unit * 1.1);
    final sofaH = unit * 0.14;
    final sofaLeft = (w - sofaW) / 2;
    final sofaTop = floorY - sofaH * 0.55;
    final sofa = Paint()..color = const Color(0xFF231A33);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(sofaLeft, sofaTop - sofaH * 0.5, sofaW, sofaH * 0.7),
        Radius.circular(sofaH * 0.25),
      ),
      sofa,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            sofaLeft - sofaH * 0.15, sofaTop, sofaW + sofaH * 0.3, sofaH * 0.6),
        Radius.circular(sofaH * 0.2),
      ),
      Paint()..color = const Color(0xFF2C2140),
    );
    // Rug.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, floorY + (h - floorY) * 0.55),
        width: sofaW * 1.1,
        height: (h - floorY) * 0.5,
      ),
      Paint()..color = const Color(0xFF3A2A55).withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant NeuraPenthousePainter oldDelegate) =>
      oldDelegate.overlay != overlay ||
      oldDelegate.showFurniture != showFurniture;
}
