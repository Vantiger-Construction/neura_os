// lib/avatar/renderers/nebula_avatar_view.dart
//
// Neura as flowing nebula energy: a softly glowing body of drifting colour,
// bright points tracing her face, hands and torso, a heartbeat core, and a
// luminous channel of seven energy points running from root to crown.
//
// Ported from the "Neura — Wellness Companion Character" design. The design's
// SVG lives on an 880 x 880 design canvas (x 520..1400, y 80..960); every
// coordinate below is in that space and scaled to the widget size.
//
// Built in: no asset, network, microphone, model or speech engine is opened.
// Time only advances while [enabled] (pass NeuraMotion.live) and the OS has not
// asked for reduced motion; otherwise she renders as a still frame. Tickers
// are muted by TickerMode, so offstage routes do not animate. Speech mouth
// movement is delegated to [NeuraMouthLayer], which owns the fresh-utterance,
// Safe Mode and lifecycle rules for every built-in face.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/neura_events_extra.dart';
import '../avatar_controller.dart';
import '../avatar_types.dart';
import 'neura_mouth_layer.dart';

/// Normalized mouth position on the nebula canvas (design point 962, 404).
const Rect kNebulaMouthBounds = Rect.fromLTWH(0.462, 0.352, 0.08, 0.034);

/// Built-in nebula-energy portrait of Neura, driven by [AvatarController].
class NebulaAvatarView extends StatefulWidget {
  const NebulaAvatarView({
    super.key,
    required this.controller,
    this.size = 128,
    this.enabled = true,
  });

  final AvatarController controller;
  final double size;

  /// When false she holds a still frame and the mouth rests.
  final bool enabled;

  @override
  State<NebulaAvatarView> createState() => _NebulaAvatarViewState();
}

class _NebulaAvatarViewState extends State<NebulaAvatarView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  double _carried = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _seconds.value = _carried + elapsed.inMicroseconds / 1e6;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(NebulaAvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.enabled && !_reduceMotion;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      // Keep the current pose; resuming continues from here, not from zero.
      _carried = _seconds.value;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'Neura nebula presence',
        child: SizedBox.square(
          dimension: widget.size,
          child: NeuraMouthLayer(
            controller: widget.controller,
            enabled: widget.enabled,
            mouthBounds: kNebulaMouthBounds,
            mouthPainter: (pose) => NebulaMouthPainter(pose),
            child: CustomPaint(
              painter: NeuraNebulaPainter(
                seconds: _seconds,
                controller: widget.controller,
              ),
            ),
          ),
        ),
      );
}

/// Paints the nebula body. [seconds] is exposed so tests can confirm that a
/// still surface never advances.
class NeuraNebulaPainter extends CustomPainter {
  NeuraNebulaPainter({required this.seconds, required this.controller})
      : super(repaint: Listenable.merge([seconds, controller]));

  final ValueNotifier<double> seconds;
  final AvatarController controller;

  static const double _left = 520;
  static const double _top = 80;
  static const double _span = 880;

  // Cloud palette (design c0..c7): violet, cyan, magenta, face lilac, teal,
  // blue, pink, amber.
  static const List<Color> _cloudCool = [
    Color(0xFF7B5CFF),
    Color(0xFF3FD3FF),
    Color(0xFFFF5FD2),
    Color(0xFFB9A7FF),
    Color(0xFF2EE6C5),
    Color(0xFF4F7CFF),
    Color(0xFFFF8AD8),
    Color(0xFFFFC46B),
  ];

  static const Color _warm = Color(0xFFFFB07A);
  static const Color _night = Color(0xFF090B1C);
  static const Color _deep = Color(0xFF04050D);

  // Clouds: center, radii, opacity (design ellipses c0..c7).
  static const List<List<double>> _clouds = [
    [900, 560, 150, 220, 0.95],
    [1040, 480, 120, 160, 0.95],
    [980, 700, 140, 110, 0.85],
    [960, 290, 90, 120, 0.75],
    [730, 660, 60, 160, 0.9],
    [1190, 520, 60, 170, 0.9],
    [1224, 400, 44, 80, 0.85],
    [700, 840, 40, 70, 0.8],
  ];

  // Seven energy points, root to crown.
  static const List<double> _chakraY = [800, 715, 630, 540, 455, 262, 165];
  static const List<Color> _chakraColors = [
    Color(0xFFFF4D4D),
    Color(0xFFFF9A3C),
    Color(0xFFFFD93C),
    Color(0xFF4CE38A),
    Color(0xFF3CB8FF),
    Color(0xFF6B5CFF),
    Color(0xFFC77DFF),
  ];

  // Bright points tracing face, hands and torso: x, y, core radius.
  static const List<List<double>> _bright = [
    [933, 290, 2.6],
    [995, 290, 2.6],
    [960, 196, 3.2],
    [905, 340, 2.2],
    [1015, 340, 2.2],
    [900, 472, 2.8],
    [1020, 472, 2.8],
    [960, 610, 2.4],
    [688, 880, 2.6],
    [704, 892, 3.0],
    [720, 878, 2.4],
    [1212, 338, 2.4],
    [1230, 326, 3.0],
    [1248, 342, 2.4],
  ];

  static final Path _silhouette = _buildSilhouette();
  static final List<_Star> _stars = _buildStars();

  static Path _oval(double cx, double cy, double rx, double ry,
      [double degrees = 0]) {
    final path = Path()
      ..addOval(Rect.fromCenter(
          center: Offset.zero, width: rx * 2, height: ry * 2));
    final matrix = Matrix4.rotationZ(degrees * math.pi / 180)
      ..setTranslationRaw(cx, cy, 0);
    return path.transform(matrix.storage);
  }

  static Path _buildSilhouette() {
    final torso = Path()
      ..moveTo(960, 450)
      ..cubicTo(1060, 450, 1130, 480, 1135, 540)
      ..cubicTo(1140, 640, 1060, 700, 1040, 800)
      ..cubicTo(1020, 880, 990, 930, 960, 952)
      ..cubicTo(930, 930, 900, 880, 880, 800)
      ..cubicTo(860, 700, 780, 640, 785, 540)
      ..cubicTo(790, 480, 860, 450, 960, 450)
      ..close();
    final parts = <Path>[
      torso,
      _oval(960, 300, 100, 125),
      _oval(960, 430, 40, 55),
      _oval(748, 672, 36, 168, 18),
      _oval(700, 848, 36, 58),
      _oval(1140, 572, 38, 90, -24),
      _oval(1196, 520, 32, 122, 10),
      _oval(1222, 390, 38, 66, 15),
    ];
    return parts.reduce((a, b) => Path.combine(PathOperation.union, a, b));
  }

  static List<_Star> _buildStars() {
    final random = math.Random(7);
    final stars = <_Star>[];
    final bounds = _silhouette.getBounds();
    while (stars.length < 72) {
      final p = Offset(
        bounds.left + random.nextDouble() * bounds.width,
        bounds.top + random.nextDouble() * bounds.height,
      );
      if (!_silhouette.contains(p)) continue;
      stars.add(_Star(
        p,
        0.8 + random.nextDouble() * 2.2,
        0.25 + random.nextDouble() * 0.6,
        random.nextDouble() * math.pi * 2,
        0.6 + random.nextDouble() * 1.6,
        _cloudCool[random.nextInt(_cloudCool.length)],
      ));
    }
    return stars;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = seconds.value;
    final s = controller.signals;
    final mood = s.mood.isFinite ? s.mood.clamp(-1.0, 1.0) : 0.0;
    final energy = s.energy.isFinite ? s.energy.clamp(0.0, 1.0) : 0.5;
    final dim = s.isError ? 0.55 : 1.0;
    final warmth = (mood * 0.5 + 0.5) * 0.35;
    final pace = s.isThinking ? 1.8 : 1.0;

    Color tint(Color c) => Color.lerp(c, _warm, warmth)!;

    canvas.save();
    canvas.scale(size.width / _span, size.height / _span);
    canvas.translate(-_left, -_top);

    // Face glow behind the head.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(958, 290), width: 300, height: 360),
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(958, 290),
          180,
          [
            Colors.white.withValues(alpha: 0.18 * dim),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );

    // Body: drifting clouds, sparkle and shading inside her silhouette.
    canvas.save();
    canvas.clipPath(_silhouette);
    canvas.drawRect(
        const Rect.fromLTWH(560, 80, 800, 880), Paint()..color = _night);
    final drift = Offset(
      math.sin(t * 0.21 * pace) * 18,
      math.cos(t * 0.17 * pace) * 14,
    );
    for (var i = 0; i < _clouds.length; i++) {
      final c = _clouds[i];
      final wobble = math.sin(t * 0.3 * pace + i) * 0.06;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c[0], c[1]) + drift * (i.isEven ? 1 : -0.7),
          width: c[2] * 2 * (1 + wobble),
          height: c[3] * 2 * (1 - wobble),
        ),
        Paint()
          ..color = tint(_cloudCool[i]).withValues(alpha: c[4] * dim)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38),
      );
    }
    for (final star in _stars) {
      final twinkle = 0.55 + 0.45 * math.sin(t * star.speed + star.phase);
      canvas.drawCircle(
        star.at + drift * 0.4,
        star.radius,
        Paint()
          ..color = tint(star.color)
              .withValues(alpha: star.opacity * twinkle * dim),
      );
    }
    canvas.drawRect(
      const Rect.fromLTWH(560, 80, 800, 880),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(960, 80),
          const Offset(960, 960),
          [
            _night.withValues(alpha: 0),
            _night.withValues(alpha: 0.15),
            _night.withValues(alpha: 0.7),
          ],
          const [0, 0.55, 1],
        ),
    );

    // Highlights and soft facial shadows, tilted with her head.
    final tilt = math.sin(t * 0.4) * 2.5 + mood * 2;
    final soft =
        Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final wide =
        Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.save();
    canvas.translate(960, 400);
    canvas.rotate(tilt * math.pi / 180);
    canvas.translate(-960, -400);
    _ellipse(canvas, 928, 232, 34, 24, soft..color = _white(0.16));
    _ellipse(canvas, 929, 294, 30, 18, soft..color = _shadow(0.5));
    _ellipse(canvas, 991, 294, 30, 18, soft..color = _shadow(0.55));
    _ellipse(canvas, 960, 384, 16, 5, soft..color = _shadow(0.4));
    _ellipse(canvas, 1016, 336, 14, 30, soft..color = _shadow(0.3));
    canvas.restore();
    _ellipse(canvas, 900, 520, 40, 70, wide..color = _white(0.08));
    _ellipse(canvas, 962, 404, 38, 14, soft..color = _shadow(0.5));
    _ellipse(canvas, 1060, 560, 40, 120, wide..color = _shadow(0.3));
    canvas.restore();

    // Heartbeat core.
    final rate = 0.8 + energy * 0.6 + (s.isTalking ? 0.3 : 0);
    final beat = math.pow(math.sin(t * math.pi * rate).abs(), 6).toDouble();
    final heartR = 24 + beat * 8 * (0.6 + energy * 0.8);
    canvas.drawCircle(
      const Offset(960, 540),
      heartR,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(960, 540),
          heartR,
          [
            Colors.white.withValues(alpha: 0.95 * dim),
            tint(const Color(0xFFFF8AD8)).withValues(alpha: 0.6 * dim),
            const Color(0x00FF8AD8),
          ],
          const [0, 0.45, 1],
        ),
    );

    // Pupils and bright points.
    for (final x in [929.0, 991.0]) {
      canvas.drawCircle(
          Offset(x, 294), 4.6, Paint()..color = const Color(0xFF05060F));
    }
    for (var i = 0; i < _bright.length; i++) {
      final b = _bright[i];
      final glint = 0.75 + 0.25 * math.sin(t * 1.3 + i * 1.7);
      final at = Offset(b[0], b[1]);
      canvas.drawCircle(
        at,
        b[2] * 4,
        Paint()
          ..color = tint(_cloudCool[i % 3]).withValues(alpha: 0.38 * dim)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
          at, b[2] * glint, Paint()..color = _white(0.95 * dim));
    }

    _paintChannel(canvas, t, s, dim);
    canvas.restore();
  }

  void _paintChannel(Canvas canvas, double t, AvatarSignals s, double dim) {
    final presence = s.isListening ? 1.0 : (s.isError ? 0.4 : 0.8);
    final points = [
      for (var i = 0; i < _chakraY.length; i++)
        Offset(960 + math.sin(t * 0.6 + i) * 3, _chakraY[i]),
    ];
    final channel = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final mid = (a.dy + b.dy) / 2;
      channel.cubicTo(a.dx, mid, b.dx, mid, b.dx, b.dy);
    }
    canvas.drawPath(
      channel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = _white(0.12 * presence * dim)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      channel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          Offset(960, _chakraY.first),
          Offset(960, _chakraY.last),
          [
            for (final c in _chakraColors)
              c.withValues(alpha: 0.7 * presence * dim),
          ],
          [for (var i = 0; i < _chakraY.length; i++) i / (_chakraY.length - 1)],
        ),
    );

    // Light rising along the channel.
    for (final metric in channel.computeMetrics()) {
      for (var k = 0; k < 3; k++) {
        final f = (t * 0.12 + k / 3) % 1.0;
        final tangent = metric.getTangentForOffset(metric.length * f);
        if (tangent == null) continue;
        canvas.drawCircle(
          tangent.position,
          3.2,
          Paint()
            ..color = _white(math.sin(f * math.pi) * 0.8 * presence * dim)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }

    for (var i = 0; i < points.length; i++) {
      final at = points[i];
      final color = _chakraColors[i];
      final pulse = 1 + 0.12 * math.sin(t * 1.6 + i * 0.9);
      final o = presence * dim;
      canvas.drawCircle(
        at,
        18 * pulse,
        Paint()
          ..color = color.withValues(alpha: 0.35 * o)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: o);
      final spin = t * (i.isEven ? 0.5 : -0.5);
      const dashes = 9;
      for (var d = 0; d < dashes; d++) {
        final start = spin + d * 2 * math.pi / dashes;
        canvas.drawArc(Rect.fromCircle(center: at, radius: 11), start,
            2 * math.pi / dashes * 0.45, false, ring);
      }
      canvas.drawCircle(at, 4.5, Paint()..color = color.withValues(alpha: o));
      canvas.drawCircle(at, 1.8, Paint()..color = _white(o));
    }
  }

  static void _ellipse(
      Canvas canvas, double cx, double cy, double rx, double ry, Paint paint) {
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
        paint);
  }

  static Color _white(double alpha) =>
      Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));
  static Color _shadow(double alpha) => _deep.withValues(alpha: alpha);

  @override
  bool shouldRepaint(NeuraNebulaPainter oldDelegate) =>
      oldDelegate.seconds != seconds || oldDelegate.controller != controller;
}

class _Star {
  const _Star(
      this.at, this.radius, this.opacity, this.phase, this.speed, this.color);
  final Offset at;
  final double radius;
  final double opacity;
  final double phase;
  final double speed;
  final Color color;
}

/// A mouth of light: a soft line at rest, a glowing opening while speaking.
class NebulaMouthPainter extends CustomPainter {
  const NebulaMouthPainter(this.pose);
  final NeuraMouthPose pose;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final glow = Paint()
      ..color = const Color(0xFF9EE7FF).withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08);
    if (pose.open == 0) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.09
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.45);
      final curve = pose.viseme == NeuraViseme.MBP ? 0.5 : 0.6;
      canvas.drawPath(
          Path()
            ..moveTo(0.12, 0.5)
            ..quadraticBezierTo(0.5, curve, 0.88, 0.5),
          line);
    } else {
      final rounded = {
        NeuraViseme.O,
        NeuraViseme.U,
        NeuraViseme.WQ,
        NeuraViseme.R,
        NeuraViseme.CHJSH,
      }.contains(pose.viseme);
      final width = rounded ? 0.5 : 0.86;
      final height = (0.12 + pose.open * 0.8).clamp(0.0, 0.95);
      final rect = Rect.fromCenter(
          center: const Offset(0.5, 0.5), width: width, height: height);
      canvas.drawOval(rect.inflate(0.06), glow);
      canvas.drawOval(rect,
          Paint()..color = Colors.white.withValues(alpha: 0.85));
      canvas.drawOval(rect.deflate(math.min(0.06, height * 0.25)),
          Paint()..color = const Color(0xFFBFF3FF));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NebulaMouthPainter oldDelegate) =>
      oldDelegate.pose != pose;
}
