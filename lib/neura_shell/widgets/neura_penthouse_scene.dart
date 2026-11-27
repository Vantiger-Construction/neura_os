import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../avatar/motion/neura_motion.dart';
import '../../mood/services/neura_mood_weather.dart';
import '../../relationships/services/promise_garden.dart';
import '../models/neura_room.dart';
import '../neura_shell_state.dart';

/// Neura's penthouse, painted in code so it needs no image assets.
///
/// Each room of her home has its own view and interior: the night skyline
/// lounge of the Penthouse, the moonlit sea of Reflection Bay, the sunset and
/// string lights of the Joy Lounge, the rain-streaked Mood Den, the starlit
/// glass roof of the Dream Atrium, the lamplit shelves of the Legacy Vault,
/// and Her Suite, Neura's own space. [room] picks which one is shown, so you
/// can see where she is.
///
/// The scene is static (no animation ticker), so it costs nothing at idle and
/// is safe for Safe Mode and reduced-motion users. When the room changes
/// while companion motion is live, the old room fades into the new one;
/// otherwise the change is instant.
///
/// [dim] lays the app background colour over the scene so it can sit behind
/// menus and content without hurting readability (0 = full scene,
/// 1 = fully hidden).
class NeuraPenthouseScene extends StatelessWidget {
  const NeuraPenthouseScene({
    super.key,
    this.room = NeuraRoom.penthouse,
    this.dim = 0,
    this.dimColor,
    this.showFurniture = true,
    this.weather,
    this.garden,
  });

  final NeuraRoom room;
  final double dim;
  final Color? dimColor;
  final bool showFurniture;

  /// The weather over the room. Null follows the user's recent mood
  /// check-ins ([NeuraMoodWeatherService]).
  final NeuraMoodWeather? weather;

  /// The plant by the lounge window. Null follows the promises the user has
  /// kept ([PromiseGardenService]).
  final PromiseGardenStage? garden;

  /// How long one room takes to fade into the next.
  static const Duration crossfade = Duration(milliseconds: 700);

  @override
  Widget build(BuildContext context) {
    final fixedGarden = garden;
    if (fixedGarden != null) return _withWeather(context, fixedGarden);
    return ValueListenableBuilder<PromiseGardenStage>(
      valueListenable: PromiseGardenService.instance.stage,
      builder: (context, value, _) => _withWeather(context, value),
    );
  }

  Widget _withWeather(BuildContext context, PromiseGardenStage plant) {
    final fixed = weather;
    if (fixed != null) return _build(context, fixed, plant);
    return ValueListenableBuilder<NeuraMoodWeather>(
      valueListenable: NeuraMoodWeatherService.instance.weather,
      builder: (context, value, _) => _build(context, value, plant),
    );
  }

  Widget _build(
    BuildContext context,
    NeuraMoodWeather weather,
    PromiseGardenStage plant,
  ) {
    final overlay = (dimColor ?? Theme.of(context).colorScheme.surface)
        .withValues(alpha: dim.clamp(0.0, 1.0));
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final animate = NeuraMotion.instance.live.value && !reduceMotion;
    final penthouse = room.id == NeuraRoom.penthouse.id
        ? context
            .dependOnInheritedWidgetOfExactType<NeuraShellScope>()
            ?.notifier
            ?.penthouse
        : null;
    final painter = NeuraPenthousePainter(
      room: room,
      overlay: overlay,
      lampOn: penthouse?.lampOn ?? true,
      curtainsClosed: penthouse?.curtainsClosed ?? false,
      showFurniture: showFurniture,
      weather: weather,
      garden: plant,
    );
    return AnimatedSwitcher(
      duration: animate ? crossfade : Duration.zero,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: RepaintBoundary(
        key: ValueKey<String>(room.id),
        child: CustomPaint(
          painter: painter,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class NeuraPenthousePainter extends CustomPainter {
  NeuraPenthousePainter({
    this.room = NeuraRoom.penthouse,
    this.lampOn = true,
    this.curtainsClosed = false,
    required this.overlay,
    required this.showFurniture,
    this.weather = NeuraMoodWeather.mild,
    this.garden = PromiseGardenStage.empty,
  });

  final NeuraRoom room;
  final bool lampOn;
  final bool curtainsClosed;
  final Color overlay;
  final bool showFurniture;
  final NeuraMoodWeather weather;
  final PromiseGardenStage garden;

  static const _skyTop = Color(0xFF070B1C);
  static const _skyMid = Color(0xFF16163A);
  static const _skyHorizon = Color(0xFF3A2350);
  static const _cityFar = Color(0xFF141631);
  static const _cityNear = Color(0xFF0B0C1F);
  static const _frame = Color(0xFF05060F);
  static const _floor = Color(0xFF0C0A16);
  static const _windowWarm = Color(0xFFFFD58A);
  static const _windowCool = Color(0xFF9FD8FF);
  static const _moonLight = Color(0xFFFFF3D6);
  static const _lampWarm = Color(0xFFFFC27A);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final floorY = h * 0.78;
    final rnd = math.Random(7);

    switch (room.id) {
      case 'reflection_bay':
        _paintSea(canvas, w, floorY, rnd);
        _paintWindowFrame(canvas, w, floorY);
        _paintFloor(canvas, w, h, floorY, const Color(0xFF2E7A8C));
        if (showFurniture) _drawBayNook(canvas, w, h, floorY);
      case 'joy_lounge':
        _paintSunset(canvas, w, floorY, rnd);
        _paintWindowFrame(canvas, w, floorY);
        _paintFloor(canvas, w, h, floorY, const Color(0xFFD9766B));
        if (showFurniture) _drawJoyLounge(canvas, w, h, floorY, rnd);
      case 'mood_den':
        _paintRain(canvas, w, floorY, rnd);
        _paintWindowFrame(canvas, w, floorY);
        _paintFloor(canvas, w, h, floorY, const Color(0xFF4A3B5C));
        if (showFurniture) _drawDen(canvas, w, h, floorY);
      case 'dream_atrium':
        _paintAtriumSky(canvas, w, floorY, rnd);
        _paintAtriumFrame(canvas, w, floorY);
        _paintFloor(canvas, w, h, floorY, const Color(0xFF5B3A9E));
        if (showFurniture) _drawAtrium(canvas, w, h, floorY);
      case 'legacy_vault':
        _paintVaultWall(canvas, w, floorY, rnd);
        _paintFloor(canvas, w, h, floorY, const Color(0xFF8C6A3E));
        if (showFurniture) _drawVaultDesk(canvas, w, h, floorY);
      case 'her_suite':
        _paintDusk(canvas, w, floorY, rnd);
        _paintWindowFrame(canvas, w, floorY);
        _paintCurtains(canvas, w, floorY);
        _paintFloor(canvas, w, h, floorY, const Color(0xFFB0785A));
        if (showFurniture) _drawSuite(canvas, w, h, floorY);
      default:
        _paintCity(canvas, w, h, floorY, rnd);
        _paintWindowFrame(canvas, w, floorY);
        _paintFloor(canvas, w, h, floorY, const Color(0xFF6B3E8C));
        if (showFurniture) {
          _drawLounge(canvas, w, h, floorY);
          _drawPromisePlant(canvas, w, h, floorY);
        }
    }

    _paintWeather(canvas, w, floorY);

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

  /// A light layer over the view from the room: subtle enough that the
  /// room still reads as itself. Static, so it costs no frames.
  void _paintWeather(Canvas canvas, double w, double floorY) {
    final view = Rect.fromLTWH(0, 0, w, floorY);
    switch (weather) {
      case NeuraMoodWeather.mild:
        return;
      case NeuraMoodWeather.clear:
        _drawGlow(
          canvas,
          Offset(w * 0.78, floorY * 0.18),
          math.max(w, floorY) * 0.55,
          const Color(0xFFFFD9A0).withValues(alpha: 0.16),
        );
      case NeuraMoodWeather.overcast:
        _fillVertical(canvas, view, <Color>[
          const Color(0xFF8A90A8).withValues(alpha: 0.20),
          const Color(0xFF8A90A8).withValues(alpha: 0.06),
        ]);
      case NeuraMoodWeather.rain:
        _fillVertical(canvas, view, <Color>[
          const Color(0xFF5E6E8C).withValues(alpha: 0.24),
          const Color(0xFF5E6E8C).withValues(alpha: 0.08),
        ]);
        final rnd = math.Random(23);
        final streak = Paint()
          ..color = const Color(0xFFCFE3FF).withValues(alpha: 0.16)
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 70; i++) {
          final x = rnd.nextDouble() * w;
          final y = rnd.nextDouble() * floorY;
          final length = 8 + rnd.nextDouble() * 14;
          if (y + length > floorY) continue;
          canvas.drawLine(
            Offset(x, y),
            Offset(x - length * 0.18, y + length),
            streak,
          );
        }
    }
  }

  // ---------------------------------------------------------------------
  // Shared pieces.

  static void _fillVertical(Canvas canvas, Rect rect, List<Color> colors) {
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  static void _drawGlow(Canvas canvas, Offset center, double r, Color color) {
    final rect = Rect.fromCircle(center: center, radius: r);
    final gradient = RadialGradient(
      colors: <Color>[color, color.withValues(alpha: 0)],
    );
    canvas.drawCircle(center, r, Paint()..shader = gradient.createShader(rect));
  }

  static void _drawStars(
    Canvas canvas,
    math.Random rnd,
    double w,
    double bottom,
    int count,
  ) {
    final star = Paint();
    for (var i = 0; i < count; i++) {
      final alpha = 0.15 + rnd.nextDouble() * 0.5;
      star.color = Colors.white.withValues(alpha: alpha);
      final at = Offset(rnd.nextDouble() * w, rnd.nextDouble() * bottom);
      canvas.drawCircle(at, 0.5 + rnd.nextDouble() * 0.9, star);
    }
  }

  static void _drawMoon(Canvas canvas, Offset moon, double moonR) {
    _drawGlow(canvas, moon, moonR * 3, _moonLight.withValues(alpha: 0.22));
    canvas.drawCircle(moon, moonR, Paint()..color = _moonLight);
  }

  void _paintWindowFrame(Canvas canvas, double w, double floorY) {
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
      Rect.fromLTWH(0, floorY - mullion, w, mullion * 1.4),
      frame,
    );
  }

  /// Polished floor with a soft reflection of the room's light.
  void _paintFloor(
    Canvas canvas,
    double w,
    double h,
    double floorY,
    Color tint,
  ) {
    final floorRect = Rect.fromLTWH(0, floorY, w, h - floorY);
    final top = Color.alphaBlend(tint.withValues(alpha: 0.25), _floor);
    _fillVertical(canvas, floorRect, <Color>[top, _floor]);
  }

  // ---------------------------------------------------------------------
  // Penthouse: night city skyline and lounge.

  void _paintCity(
    Canvas canvas,
    double w,
    double h,
    double floorY,
    math.Random rnd,
  ) {
    final sky = Rect.fromLTWH(0, 0, w, floorY);
    _fillVertical(canvas, sky, const <Color>[_skyTop, _skyMid, _skyHorizon]);
    _drawStars(canvas, rnd, w, floorY * 0.45, 70);
    final moonR = math.max(8.0, math.min(w, h) * 0.035);
    _drawMoon(canvas, Offset(w * 0.78, floorY * 0.16), moonR);

    // Two layers of skyline with lit windows.
    _drawSkyline(
      canvas,
      w,
      floorY,
      rnd,
      baseline: floorY * 0.98,
      minH: floorY * 0.18,
      maxH: floorY * 0.42,
      color: _cityFar,
      litChance: 0.18,
    );
    _drawSkyline(
      canvas,
      w,
      floorY,
      rnd,
      baseline: floorY,
      minH: floorY * 0.10,
      maxH: floorY * 0.30,
      color: _cityNear,
      litChance: 0.28,
    );

    // Horizon glow from the city.
    final glow = Rect.fromLTWH(0, floorY * 0.7, w, floorY * 0.3);
    final purple = const Color(0xFFB25FD6).withValues(alpha: 0.18);
    _fillVertical(canvas, glow, <Color>[Colors.transparent, purple]);
  }

  // ---------------------------------------------------------------------
  // Reflection Bay: a moonlit sea and a low reading nook.

  void _paintSea(Canvas canvas, double w, double floorY, math.Random rnd) {
    final horizon = floorY * 0.58;
    final sky = Rect.fromLTWH(0, 0, w, horizon);
    const skyColors = <Color>[
      Color(0xFF04101A),
      Color(0xFF0B2733),
      Color(0xFF1C4E6B),
    ];
    _fillVertical(canvas, sky, skyColors);
    _drawStars(canvas, rnd, w, horizon * 0.7, 45);
    final moonX = w * 0.3;
    final moonR = math.max(8.0, math.min(w, floorY) * 0.04);
    _drawMoon(canvas, Offset(moonX, horizon * 0.32), moonR);

    final sea = Rect.fromLTWH(0, horizon, w, floorY - horizon);
    const seaColors = <Color>[Color(0xFF0E3446), Color(0xFF041019)];
    _fillVertical(canvas, sea, seaColors);

    // Moon path on the water, then a few long wave lines.
    final shimmer = Paint();
    for (var y = horizon + 3; y < floorY - 4; y += 5) {
      final depth = (y - horizon) / (floorY - horizon);
      final half = moonR * (0.6 + depth * 2.4) * (0.6 + rnd.nextDouble());
      final alpha = 0.45 * (1 - depth) + 0.08;
      shimmer.color = _moonLight.withValues(alpha: alpha);
      final rect = Rect.fromLTWH(moonX - half, y, half * 2, 1.4);
      canvas.drawRect(rect, shimmer);
    }
    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF9FD8FF).withValues(alpha: 0.12);
    for (var i = 1; i <= 4; i++) {
      final y = horizon + (floorY - horizon) * i / 5;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= w; x += w / 8) {
        path.quadraticBezierTo(x + w / 32, y - 2, x + w / 16, y);
      }
      canvas.drawPath(path, wave);
    }
  }

  void _drawBayNook(Canvas canvas, double w, double h, double floorY) {
    final unit = math.min(w, h);
    final cushion = Paint()..color = const Color(0xFF17323F);
    for (final dx in <double>[-0.16, 0.0, 0.16]) {
      final rect = Rect.fromCenter(
        center: Offset(w * 0.5 + unit * dx, floorY + unit * 0.02),
        width: unit * 0.14,
        height: unit * 0.06,
      );
      canvas.drawOval(rect, cushion);
    }
    final table = Rect.fromCenter(
      center: Offset(w * 0.5, floorY + unit * 0.08),
      width: unit * 0.26,
      height: unit * 0.035,
    );
    final tableRadius = Radius.circular(unit * 0.01);
    final tableShape = RRect.fromRectAndRadius(table, tableRadius);
    canvas.drawRRect(tableShape, Paint()..color = const Color(0xFF0D1F28));
    final flame = Offset(w * 0.5, table.top - unit * 0.012);
    _drawGlow(canvas, flame, unit * 0.12, _lampWarm.withValues(alpha: 0.28));
    final candle = Rect.fromCenter(
      center: Offset(flame.dx, table.top - unit * 0.004),
      width: unit * 0.012,
      height: unit * 0.016,
    );
    canvas.drawRect(candle, Paint()..color = const Color(0xFFEAD9B8));
    canvas.drawCircle(flame, unit * 0.005, Paint()..color = _lampWarm);
  }

  // ---------------------------------------------------------------------
  // Joy Lounge: a warm sunset over low hills and strings of lights.

  void _paintSunset(Canvas canvas, double w, double floorY, math.Random rnd) {
    final sky = Rect.fromLTWH(0, 0, w, floorY);
    const skyColors = <Color>[
      Color(0xFF1B0B2D),
      Color(0xFF6B2A6E),
      Color(0xFFE0745A),
      Color(0xFFFFB86B),
    ];
    _fillVertical(canvas, sky, skyColors);
    final sun = Offset(w * 0.62, floorY * 0.72);
    final sunR = math.max(14.0, math.min(w, floorY) * 0.09);
    _drawGlow(canvas, sun, sunR * 3, const Color(0x66FFD27A));
    canvas.drawCircle(sun, sunR, Paint()..color = const Color(0xFFFFD9A0));

    // Rolling hills in front of the sun.
    final hills = Path()..moveTo(0, floorY);
    var x = 0.0;
    final y = floorY * 0.82;
    hills.lineTo(0, y);
    while (x < w) {
      final step = w * (0.12 + rnd.nextDouble() * 0.12);
      final peak = floorY * (0.74 + rnd.nextDouble() * 0.1);
      hills.quadraticBezierTo(x + step / 2, peak, x + step, y);
      x += step;
    }
    hills.lineTo(w, floorY);
    hills.close();
    canvas.drawPath(hills, Paint()..color = const Color(0xFF3A1838));
  }

  void _drawJoyLounge(
    Canvas canvas,
    double w,
    double h,
    double floorY,
    math.Random rnd,
  ) {
    final unit = math.min(w, h);
    const bulbs = <Color>[
      Color(0xFFFFD27A),
      Color(0xFFFF8AD8),
      Color(0xFF9FD8FF),
      Color(0xFFB9F6A8),
    ];
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF2A1A30);
    for (final sag in <double>[0.12, 0.2]) {
      final top = floorY * 0.04;
      final low = floorY * sag;
      final path = Path()
        ..moveTo(0, top)
        ..quadraticBezierTo(w / 2, low * 2 - top, w, top);
      canvas.drawPath(path, wire);
      for (final metric in path.computeMetrics()) {
        final count = math.max(6, (w / 70).round());
        for (var i = 1; i < count; i++) {
          final offset = metric.length * i / count;
          final tangent = metric.getTangentForOffset(offset);
          if (tangent == null) continue;
          final color = bulbs[(i + rnd.nextInt(2)) % bulbs.length];
          final at = tangent.position + const Offset(0, 4);
          _drawGlow(canvas, at, unit * 0.03, color.withValues(alpha: 0.45));
          canvas.drawCircle(at, 2.2, Paint()..color = color);
        }
      }
    }

    // Two round lounge chairs and a low table between them.
    final chair = Paint()..color = const Color(0xFF3A1E4A);
    for (final dx in <double>[-0.22, 0.22]) {
      final rect = Rect.fromCenter(
        center: Offset(w * 0.5 + unit * dx, floorY - unit * 0.02),
        width: unit * 0.2,
        height: unit * 0.16,
      );
      canvas.drawOval(rect, chair);
    }
    final table = Rect.fromCenter(
      center: Offset(w * 0.5, floorY + unit * 0.02),
      width: unit * 0.14,
      height: unit * 0.05,
    );
    canvas.drawOval(table, Paint()..color = const Color(0xFF5A2E52));
  }

  // ---------------------------------------------------------------------
  // Mood Den: rain on the glass, a soft city blur and a reading chair.

  void _paintRain(Canvas canvas, double w, double floorY, math.Random rnd) {
    final sky = Rect.fromLTWH(0, 0, w, floorY);
    const skyColors = <Color>[
      Color(0xFF0A0F1E),
      Color(0xFF1A1F3A),
      Color(0xFF3B2B4A),
    ];
    _fillVertical(canvas, sky, skyColors);
    _drawSkyline(
      canvas,
      w,
      floorY,
      rnd,
      baseline: floorY,
      minH: floorY * 0.14,
      maxH: floorY * 0.36,
      color: const Color(0xFF1C1A33),
      litChance: 0.08,
    );
    final mist = Rect.fromLTWH(0, floorY * 0.4, w, floorY * 0.6);
    const mistColors = <Color>[Color(0x00515A7A), Color(0x55515A7A)];
    _fillVertical(canvas, mist, mistColors);

    final streak = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final count = math.max(40, (w * floorY / 2600).round());
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * floorY;
      final len = 8 + rnd.nextDouble() * 18;
      final alpha = 0.08 + rnd.nextDouble() * 0.16;
      streak.color = const Color(0xFFB8C8FF).withValues(alpha: alpha);
      final end = Offset(x - len * 0.12, math.min(floorY, y + len));
      canvas.drawLine(Offset(x, y), end, streak);
    }
    final drop = Paint();
    for (var i = 0; i < count ~/ 3; i++) {
      final at = Offset(rnd.nextDouble() * w, rnd.nextDouble() * floorY);
      final alpha = 0.12 + rnd.nextDouble() * 0.2;
      drop.color = const Color(0xFFDCE4FF).withValues(alpha: alpha);
      canvas.drawCircle(at, 0.8 + rnd.nextDouble() * 1.4, drop);
    }
  }

  void _drawDen(Canvas canvas, double w, double h, double floorY) {
    final unit = math.min(w, h);
    final lampX = w * 0.82;
    final lampTop = floorY - unit * 0.32;
    final glow = Offset(lampX, lampTop + unit * 0.03);
    _drawGlow(canvas, glow, unit * 0.26, _lampWarm.withValues(alpha: 0.22));
    final stand = Rect.fromLTWH(lampX - 1.5, lampTop, 3, floorY - lampTop);
    canvas.drawRect(stand, Paint()..color = const Color(0xFF1A1424));
    final shade = Rect.fromCenter(
      center: Offset(lampX, lampTop + unit * 0.02),
      width: unit * 0.08,
      height: unit * 0.05,
    );
    canvas.drawOval(shade, Paint()..color = const Color(0xFFE8B98A));

    // A deep armchair with a draped blanket.
    final chairLeft = w * 0.5 - unit * 0.17;
    final back = Rect.fromLTWH(
      chairLeft,
      floorY - unit * 0.24,
      unit * 0.34,
      unit * 0.2,
    );
    final soft = Radius.circular(unit * 0.05);
    final chair = Paint()..color = const Color(0xFF2B2140);
    canvas.drawRRect(RRect.fromRectAndRadius(back, soft), chair);
    final seat = Rect.fromLTWH(
      chairLeft - unit * 0.03,
      floorY - unit * 0.1,
      unit * 0.4,
      unit * 0.11,
    );
    final seatPaint = Paint()..color = const Color(0xFF332650);
    canvas.drawRRect(RRect.fromRectAndRadius(seat, soft), seatPaint);
    final blanket = Path()
      ..moveTo(chairLeft + unit * 0.2, floorY - unit * 0.24)
      ..quadraticBezierTo(
        chairLeft + unit * 0.3,
        floorY - unit * 0.12,
        chairLeft + unit * 0.26,
        floorY - unit * 0.01,
      )
      ..lineTo(chairLeft + unit * 0.34, floorY - unit * 0.01)
      ..lineTo(chairLeft + unit * 0.34, floorY - unit * 0.24)
      ..close();
    canvas.drawPath(blanket, Paint()..color = const Color(0xFF4E3A66));
  }

  // ---------------------------------------------------------------------
  // Dream Atrium: a glass roof full of stars and a soft aurora.

  void _paintAtriumSky(
    Canvas canvas,
    double w,
    double floorY,
    math.Random rnd,
  ) {
    final sky = Rect.fromLTWH(0, 0, w, floorY);
    const skyColors = <Color>[
      Color(0xFF05051A),
      Color(0xFF1B1440),
      Color(0xFF3A1C5C),
    ];
    _fillVertical(canvas, sky, skyColors);
    _drawStars(canvas, rnd, w, floorY * 0.9, 160);

    const aurora = <Color>[Color(0x003FD3FF), Color(0x403FD3FF)];
    const auroraPink = <Color>[Color(0x00C77DFF), Color(0x33C77DFF)];
    for (var band = 0; band < 3; band++) {
      final base = floorY * (0.22 + band * 0.12);
      final path = Path()..moveTo(0, base);
      for (var x = 0.0; x <= w; x += w / 6) {
        final lift = floorY * (0.04 + rnd.nextDouble() * 0.06);
        path.quadraticBezierTo(x + w / 12, base - lift, x + w / 6, base);
      }
      path.lineTo(w, base + floorY * 0.12);
      path.lineTo(0, base + floorY * 0.12);
      path.close();
      final bounds = path.getBounds();
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: band.isEven ? aurora : auroraPink,
      );
      final paint = Paint()..shader = gradient.createShader(bounds);
      canvas.drawPath(path, paint);
    }
  }

  void _paintAtriumFrame(Canvas canvas, double w, double floorY) {
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, w * 0.005)
      ..color = _frame;
    // Ribs of the glass roof meet above the room's centre.
    final apex = Offset(w / 2, -floorY * 0.6);
    for (var i = 0; i <= 8; i++) {
      final foot = Offset(w * i / 8, floorY);
      canvas.drawLine(apex, foot, frame);
    }
    for (final y in <double>[0.3, 0.62]) {
      canvas.drawLine(Offset(0, floorY * y), Offset(w, floorY * y), frame);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, floorY - 3, w, 4),
      Paint()..color = _frame,
    );
  }

  void _drawAtrium(Canvas canvas, double w, double h, double floorY) {
    final unit = math.min(w, h);
    // A round reflecting pool catching the starlight.
    final pool = Rect.fromCenter(
      center: Offset(w / 2, floorY + (h - floorY) * 0.45),
      width: math.min(w * 0.6, unit * 0.9),
      height: (h - floorY) * 0.45,
    );
    const poolColors = <Color>[Color(0xFF2A2060), Color(0xFF0E0B26)];
    const gradient = RadialGradient(colors: poolColors);
    final water = Paint()..shader = gradient.createShader(pool);
    canvas.drawOval(pool, water);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFC77DFF).withValues(alpha: 0.35);
    canvas.drawOval(pool, rim);

    // Hanging plants from the roof.
    final vine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF1E3A2E);
    final leaf = Paint()..color = const Color(0xFF2E5A44);
    for (final fx in <double>[0.14, 0.86]) {
      final x = w * fx;
      final bottom = floorY * 0.42;
      canvas.drawLine(Offset(x, 0), Offset(x, bottom), vine);
      for (var y = floorY * 0.08; y < bottom; y += unit * 0.035) {
        final rect = Rect.fromCenter(
          center: Offset(x + (y.round().isEven ? 5 : -5), y),
          width: unit * 0.03,
          height: unit * 0.015,
        );
        canvas.drawOval(rect, leaf);
      }
    }
  }

  // ---------------------------------------------------------------------
  // Legacy Vault: lamplit shelves of kept things, no window.

  void _paintVaultWall(
    Canvas canvas,
    double w,
    double floorY,
    math.Random rnd,
  ) {
    final wall = Rect.fromLTWH(0, 0, w, floorY);
    const wallColors = <Color>[
      Color(0xFF070A10),
      Color(0xFF141A28),
      Color(0xFF1E1A1A),
    ];
    _fillVertical(canvas, wall, wallColors);

    final shelf = Paint()..color = const Color(0xFF2A2018);
    const rows = 4;
    final shelfTop = floorY * 0.14;
    final rowH = (floorY * 0.8 - shelfTop) / rows;
    const keepsakes = <Color>[
      Color(0xFF6B4E3A),
      Color(0xFF3A4E6B),
      Color(0xFF5A3A5E),
      Color(0xFF8C7A5A),
      Color(0xFF2E4A3E),
    ];
    for (var r = 0; r < rows; r++) {
      final y = shelfTop + rowH * (r + 1);
      canvas.drawRect(Rect.fromLTWH(w * 0.06, y, w * 0.88, 3), shelf);
      var x = w * 0.08;
      while (x < w * 0.9) {
        final bw = 6 + rnd.nextDouble() * 18;
        final bh = rowH * (0.35 + rnd.nextDouble() * 0.5);
        final color = keepsakes[rnd.nextInt(keepsakes.length)];
        final item = Rect.fromLTWH(x, y - bh, bw, bh);
        canvas.drawRect(item, Paint()..color = color.withValues(alpha: 0.8));
        x += bw + 2 + rnd.nextDouble() * 10;
      }
    }
    // Small lights picking out a few treasured pieces.
    for (final fx in <double>[0.22, 0.5, 0.78]) {
      final at = Offset(w * fx, shelfTop + rowH * 0.4);
      _drawGlow(canvas, at, rowH * 1.4, _lampWarm.withValues(alpha: 0.18));
    }
  }

  void _drawVaultDesk(Canvas canvas, double w, double h, double floorY) {
    final unit = math.min(w, h);
    final desk = Rect.fromLTWH(
      w * 0.5 - unit * 0.24,
      floorY - unit * 0.1,
      unit * 0.48,
      unit * 0.035,
    );
    final wood = Paint()..color = const Color(0xFF3A2A1C);
    canvas.drawRect(desk, wood);
    for (final dx in <double>[0.02, 0.44]) {
      final leg = Rect.fromLTWH(
        desk.left + unit * dx,
        desk.bottom,
        unit * 0.02,
        floorY - desk.bottom,
      );
      canvas.drawRect(leg, wood);
    }
    final lamp = Offset(desk.left + unit * 0.08, desk.top - unit * 0.05);
    _drawGlow(canvas, lamp, unit * 0.2, _lampWarm.withValues(alpha: 0.3));
    final shade = Rect.fromCenter(
      center: lamp,
      width: unit * 0.06,
      height: unit * 0.03,
    );
    canvas.drawOval(shade, Paint()..color = const Color(0xFFE8C48A));
    final book = Rect.fromLTWH(
      desk.left + unit * 0.24,
      desk.top - unit * 0.015,
      unit * 0.12,
      unit * 0.015,
    );
    canvas.drawRect(book, Paint()..color = const Color(0xFF6B3A3A));
  }

  // ---------------------------------------------------------------------
  // Her Suite: Neura's own room, lavender dusk, sheer curtains, plants and
  // a floating orb lamp in her nebula colours.

  void _paintDusk(Canvas canvas, double w, double floorY, math.Random rnd) {
    final sky = Rect.fromLTWH(0, 0, w, floorY);
    const skyColors = <Color>[
      Color(0xFF0E0A1C),
      Color(0xFF3A2852),
      Color(0xFF8A5A7A),
      Color(0xFFD99A7A),
    ];
    _fillVertical(canvas, sky, skyColors);
    _drawStars(canvas, rnd, w, floorY * 0.35, 30);
    final hills = Rect.fromLTWH(0, floorY * 0.88, w, floorY * 0.12);
    canvas.drawRect(hills, Paint()..color = const Color(0xFF2A1A2A));
  }

  void _paintCurtains(Canvas canvas, double w, double floorY,
      {bool closed = false}) {
    final width = w * (closed ? 0.5 : 0.12);
    const sheer = <Color>[Color(0x55F2DCE8), Color(0x22F2DCE8)];
    for (final left in <double>[0, w - width]) {
      final rect = Rect.fromLTWH(left, 0, width, floorY);
      final gradient = LinearGradient(
          colors:
              closed ? const [Color(0xFF292135), Color(0xFF48364E)] : sheer);
      canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
      final fold = Paint()..color = const Color(0x22FFFFFF);
      for (var x = left + width / 5; x < left + width; x += width / 5) {
        canvas.drawRect(Rect.fromLTWH(x, 0, 1, floorY), fold);
      }
    }
  }

  void _drawSuite(Canvas canvas, double w, double h, double floorY) {
    final unit = math.min(w, h);

    // Floating orb lamp: violet, cyan and pink like her nebula form.
    final orb = Offset(w * 0.24, floorY - unit * 0.3);
    _drawGlow(canvas, orb, unit * 0.22, const Color(0x557B5CFF));
    _drawGlow(canvas, orb, unit * 0.1, const Color(0x883FD3FF));
    _drawGlow(canvas, orb, unit * 0.05, const Color(0xCCFF8AD8));
    canvas.drawCircle(orb, unit * 0.012, Paint()..color = Colors.white);

    // A low daybed with cushions.
    final bedLeft = w * 0.5 - unit * 0.2;
    final base = Rect.fromLTWH(
      bedLeft,
      floorY - unit * 0.08,
      unit * 0.5,
      unit * 0.08,
    );
    final soft = Radius.circular(unit * 0.03);
    final bed = Paint()..color = const Color(0xFF3A2A3E);
    canvas.drawRRect(RRect.fromRectAndRadius(base, soft), bed);
    final back = Rect.fromLTWH(
      bedLeft + unit * 0.38,
      floorY - unit * 0.2,
      unit * 0.12,
      unit * 0.14,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(back, soft), bed);
    final cushion = Paint()..color = const Color(0xFF8A5A7A);
    for (final dx in <double>[0.08, 0.2]) {
      final rect = Rect.fromCenter(
        center: Offset(bedLeft + unit * dx, floorY - unit * 0.1),
        width: unit * 0.1,
        height: unit * 0.05,
      );
      canvas.drawOval(rect, cushion);
    }

    // A potted plant by the window.
    final potX = w * 0.84;
    final pot = Rect.fromLTWH(
      potX - unit * 0.03,
      floorY - unit * 0.06,
      unit * 0.06,
      unit * 0.06,
    );
    canvas.drawRect(pot, Paint()..color = const Color(0xFF5A3A2A));
    final leaf = Paint()..color = const Color(0xFF2E5A44);
    for (var i = 0; i < 7; i++) {
      final angle = -math.pi / 2 + (i - 3) * 0.32;
      final reach = unit * (0.09 + (i % 2) * 0.03);
      final tip = Offset(
        potX + math.cos(angle) * reach,
        pot.top + math.sin(angle) * reach,
      );
      final mid = Offset.lerp(Offset(potX, pot.top), tip, 0.6)!;
      final rect = Rect.fromCenter(
        center: mid,
        width: unit * 0.035,
        height: unit * 0.06,
      );
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(angle + math.pi / 2);
      canvas.translate(-mid.dx, -mid.dy);
      canvas.drawOval(rect, leaf);
      canvas.restore();
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
    if (lampOn) {
      _drawGlow(canvas, Offset(lampX, lampTop + unit * 0.04), unit * 0.32,
          const Color(0xFFFFC27A).withValues(alpha: 0.30));
    }
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
    canvas.drawPath(
        shade,
        Paint()
          ..color = lampOn ? const Color(0xFFFFD9A0) : const Color(0xFF695A51));

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

  /// The plant that grows with kept promises, in a pot by the window. It
  /// only grows, and nothing is drawn until the first promise is kept.
  void _drawPromisePlant(Canvas canvas, double w, double h, double floorY) {
    if (garden == PromiseGardenStage.empty) return;
    final unit = math.min(w, h);
    final baseX = w * 0.9;
    final potW = unit * 0.07;
    final potH = unit * 0.06;
    final potTop = floorY - potH;
    final pot = Path()
      ..moveTo(baseX - potW / 2, potTop)
      ..lineTo(baseX + potW / 2, potTop)
      ..lineTo(baseX + potW * 0.36, floorY)
      ..lineTo(baseX - potW * 0.36, floorY)
      ..close();
    canvas.drawPath(pot, Paint()..color = const Color(0xFF6E4A3A));
    canvas.drawRect(
      Rect.fromLTWH(
        baseX - potW * 0.55,
        potTop - potH * 0.15,
        potW * 1.1,
        potH * 0.22,
      ),
      Paint()..color = const Color(0xFF805846),
    );

    const leafColor = Color(0xFF6FBF7A);
    final leaf = Paint()..color = leafColor;
    if (garden == PromiseGardenStage.seed) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(baseX, potTop - potH * 0.2),
          width: potW * 0.3,
          height: potH * 0.3,
        ),
        leaf,
      );
      return;
    }

    const heights = <PromiseGardenStage, double>{
      PromiseGardenStage.sprout: 0.10,
      PromiseGardenStage.leafy: 0.18,
      PromiseGardenStage.blooming: 0.24,
    };
    const leafPairs = <PromiseGardenStage, int>{
      PromiseGardenStage.sprout: 1,
      PromiseGardenStage.leafy: 3,
      PromiseGardenStage.blooming: 4,
    };
    final stemH = unit * (heights[garden] ?? 0.1);
    final stemTop = potTop - stemH;
    canvas.drawLine(
      Offset(baseX, potTop),
      Offset(baseX, stemTop),
      Paint()
        ..color = const Color(0xFF4E8F58)
        ..strokeWidth = math.max(1.5, unit * 0.006)
        ..strokeCap = StrokeCap.round,
    );

    final pairs = leafPairs[garden] ?? 1;
    final leafW = unit * 0.045;
    final leafH = unit * 0.02;
    for (var i = 0; i < pairs; i++) {
      final y = stemTop + stemH * (i / pairs) + leafH;
      for (final side in <double>[-1, 1]) {
        canvas.save();
        canvas.translate(baseX + side * leafW * 0.45, y);
        canvas.rotate(side * -0.5);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: leafW, height: leafH),
          leaf,
        );
        canvas.restore();
      }
    }

    if (garden == PromiseGardenStage.blooming) {
      final flower = Offset(baseX, stemTop);
      _drawGlow(
        canvas,
        flower,
        unit * 0.08,
        const Color(0xFFFFB7D5).withValues(alpha: 0.25),
      );
      final petal = Paint()..color = const Color(0xFFFFB7D5);
      final petals = <Offset>[
        Offset(0, -leafH * 0.6),
        Offset(-leafW * 0.6, leafH * 1.6),
        Offset(leafW * 0.6, leafH * 2.4),
      ];
      for (final offset in petals) {
        canvas.drawCircle(flower + offset, unit * 0.012, petal);
      }
    }
  }

  @override
  bool shouldRepaint(covariant NeuraPenthousePainter oldDelegate) {
    return oldDelegate.room.id != room.id ||
        oldDelegate.overlay != overlay ||
        oldDelegate.weather != weather ||
        oldDelegate.garden != garden ||
        oldDelegate.lampOn != lampOn ||
        oldDelegate.curtainsClosed != curtainsClosed ||
        oldDelegate.showFurniture != showFurniture;
  }
}
