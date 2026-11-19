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
// Time only advances while [NebulaAvatarView.enabled] (pass NeuraMotion.live)
// and the OS has not asked for reduced motion; otherwise she holds a still
// frame. Tickers are muted by TickerMode, so offstage routes do not animate.
// Speech mouth movement is delegated to [NeuraMouthLayer], which owns the
// fresh-utterance, Safe Mode and lifecycle rules for every built-in face.

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
    _ticker = createTicker(_onTick);
  }

  void _onTick(Duration elapsed) {
    _seconds.value = _carried + elapsed.inMicroseconds / 1e6;
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
  Widget build(BuildContext context) {
    final painter = NeuraNebulaPainter(
      seconds: _seconds,
      controller: widget.controller,
    );
    return Semantics(
      image: true,
      label: 'Neura nebula presence',
      child: SizedBox.square(
        dimension: widget.size,
        child: NeuraMouthLayer(
          controller: widget.controller,
          enabled: widget.enabled,
          mouthBounds: kNebulaMouthBounds,
          mouthPainter: NebulaMouthPainter.new,
          child: CustomPaint(painter: painter),
        ),
      ),
    );
  }
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
  static const Rect _bodyRect = Rect.fromLTWH(560, 80, 800, 880);
  static const Offset _heart = Offset(960, 540);
  static const int _dashes = 9;
  static const double _dashStep = 2 * math.pi / _dashes;

  // Cloud palette (design c0..c7): violet, cyan, magenta, face lilac, teal,
  // blue, pink, amber.
  static const List<Color> _cloudColors = [
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
  static const Color _night0 = Color(0x00090B1C);
  static const Color _night15 = Color(0x26090B1C);
  static const Color _night70 = Color(0xB3090B1C);
  static const Color _deep = Color(0xFF04050D);

  // Clouds (design ellipses c0..c7): center x, y, radius x, y, opacity.
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

  // Silhouette ovals: center x, y, radius x, y, rotation in degrees.
  // Head, neck, left arm and hand, right upper arm, forearm and raised hand.
  static const List<List<double>> _limbs = [
    [960, 300, 100, 125, 0],
    [960, 430, 40, 55, 0],
    [748, 672, 36, 168, 18],
    [700, 848, 36, 58, 0],
    [1140, 572, 38, 90, -24],
    [1196, 520, 32, 122, 10],
    [1222, 390, 38, 66, 15],
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

  static Path _oval(List<double> o) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: o[2] * 2,
      height: o[3] * 2,
    );
    final matrix = Matrix4.rotationZ(o[4] * math.pi / 180);
    matrix.setTranslationRaw(o[0], o[1], 0);
    return (Path()..addOval(rect)).transform(matrix.storage);
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
    final parts = [torso, for (final limb in _limbs) _oval(limb)];
    return parts.reduce((a, b) => Path.combine(PathOperation.union, a, b));
  }

  static List<_Star> _buildStars() {
    final random = math.Random(7);
    final stars = <_Star>[];
    final bounds = _silhouette.getBounds();
    while (stars.length < 72) {
      final x = bounds.left + random.nextDouble() * bounds.width;
      final y = bounds.top + random.nextDouble() * bounds.height;
      final at = Offset(x, y);
      if (!_silhouette.contains(at)) continue;
      final star = _Star(
        at: at,
        radius: 0.8 + random.nextDouble() * 2.2,
        opacity: 0.25 + random.nextDouble() * 0.6,
        phase: random.nextDouble() * math.pi * 2,
        speed: 0.6 + random.nextDouble() * 1.6,
        color: _cloudColors[random.nextInt(_cloudColors.length)],
      );
      stars.add(star);
    }
    return stars;
  }

  static Paint _fill(Color color, [double blur = 0]) {
    final paint = Paint()..color = color;
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    return paint;
  }

  static Paint _stroke(Color color, double width, [double blur = 0]) {
    final paint = _fill(color, blur);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = width;
    paint.strokeCap = StrokeCap.round;
    return paint;
  }

  static void _ellipse(Canvas canvas, List<double> e, Paint paint) {
    final rect = Rect.fromCenter(
      center: Offset(e[0], e[1]),
      width: e[2] * 2,
      height: e[3] * 2,
    );
    canvas.drawOval(rect, paint);
  }

  static Color _white(double alpha) {
    return Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  static Color _shadow(double alpha) {
    return _deep.withValues(alpha: alpha);
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

    Color tint(Color c) {
      return Color.lerp(c, _warm, warmth)!;
    }

    canvas.save();
    canvas.scale(size.width / _span, size.height / _span);
    canvas.translate(-_left, -_top);

    // Face glow behind the head.
    final faceGlow = ui.Gradient.radial(
      const Offset(958, 290),
      180,
      [_white(0.18 * dim), _white(0)],
    );
    final faceRect = Rect.fromCenter(
      center: const Offset(958, 290),
      width: 300,
      height: 360,
    );
    canvas.drawOval(faceRect, Paint()..shader = faceGlow);

    // Body: drifting clouds, sparkle and shading inside her silhouette.
    canvas.save();
    canvas.clipPath(_silhouette);
    canvas.drawRect(_bodyRect, _fill(_night));
    final drift = Offset(
      math.sin(t * 0.21 * pace) * 18,
      math.cos(t * 0.17 * pace) * 14,
    );
    for (var i = 0; i < _clouds.length; i++) {
      final c = _clouds[i];
      final wobble = math.sin(t * 0.3 * pace + i) * 0.06;
      final center = Offset(c[0], c[1]) + drift * (i.isEven ? 1 : -0.7);
      final rect = Rect.fromCenter(
        center: center,
        width: c[2] * 2 * (1 + wobble),
        height: c[3] * 2 * (1 - wobble),
      );
      final color = tint(_cloudColors[i]).withValues(alpha: c[4] * dim);
      canvas.drawOval(rect, _fill(color, 38));
    }
    for (final star in _stars) {
      final twinkle = 0.55 + 0.45 * math.sin(t * star.speed + star.phase);
      final alpha = star.opacity * twinkle * dim;
      final color = tint(star.color).withValues(alpha: alpha);
      canvas.drawCircle(star.at + drift * 0.4, star.radius, _fill(color));
    }
    final shade = ui.Gradient.linear(
      const Offset(960, 80),
      const Offset(960, 960),
      [_night0, _night15, _night70],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(_bodyRect, Paint()..shader = shade);

    // Highlights and soft facial shadows, tilted with her head.
    final tilt = math.sin(t * 0.4) * 2.5 + mood * 2;
    canvas.save();
    canvas.translate(960, 400);
    canvas.rotate(tilt * math.pi / 180);
    canvas.translate(-960, -400);
    _ellipse(canvas, const [928, 232, 34, 24], _fill(_white(0.16), 6));
    _ellipse(canvas, const [929, 294, 30, 18], _fill(_shadow(0.5), 6));
    _ellipse(canvas, const [991, 294, 30, 18], _fill(_shadow(0.55), 6));
    _ellipse(canvas, const [960, 384, 16, 5], _fill(_shadow(0.4), 6));
    _ellipse(canvas, const [1016, 336, 14, 30], _fill(_shadow(0.3), 6));
    canvas.restore();
    _ellipse(canvas, const [900, 520, 40, 70], _fill(_white(0.08), 18));
    _ellipse(canvas, const [962, 404, 38, 14], _fill(_shadow(0.5), 6));
    _ellipse(canvas, const [1060, 560, 40, 120], _fill(_shadow(0.3), 18));
    canvas.restore();

    // Heartbeat core.
    final rate = 0.8 + energy * 0.6 + (s.isTalking ? 0.3 : 0.0);
    final wave = math.sin(t * math.pi * rate).abs();
    final beat = math.pow(wave, 6).toDouble();
    final heartR = 24 + beat * 8 * (0.6 + energy * 0.8);
    final pink = tint(const Color(0xFFFF8AD8)).withValues(alpha: 0.6 * dim);
    final core = ui.Gradient.radial(
      _heart,
      heartR,
      [_white(0.95 * dim), pink, const Color(0x00FF8AD8)],
      const [0.0, 0.45, 1.0],
    );
    canvas.drawCircle(_heart, heartR, Paint()..shader = core);

    // Pupils and bright points.
    final pupil = _fill(const Color(0xFF05060F));
    canvas.drawCircle(const Offset(929, 294), 4.6, pupil);
    canvas.drawCircle(const Offset(991, 294), 4.6, pupil);
    for (var i = 0; i < _bright.length; i++) {
      final b = _bright[i];
      final at = Offset(b[0], b[1]);
      final glint = 0.75 + 0.25 * math.sin(t * 1.3 + i * 1.7);
      final halo = tint(_cloudColors[i % 3]).withValues(alpha: 0.38 * dim);
      canvas.drawCircle(at, b[2] * 4, _fill(halo, 6));
      canvas.drawCircle(at, b[2] * glint, _fill(_white(0.95 * dim)));
    }

    _paintChannel(canvas, t, s, dim);
    canvas.restore();
  }

  void _paintChannel(Canvas canvas, double t, AvatarSignals s, double dim) {
    final presence = s.isListening ? 1.0 : (s.isError ? 0.4 : 0.8);
    final o = presence * dim;
    final points = <Offset>[];
    for (var i = 0; i < _chakraY.length; i++) {
      points.add(Offset(960 + math.sin(t * 0.6 + i) * 3, _chakraY[i]));
    }
    final channel = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final mid = (a.dy + b.dy) / 2;
      channel.cubicTo(a.dx, mid, b.dx, mid, b.dx, b.dy);
    }
    canvas.drawPath(channel, _stroke(_white(0.12 * o), 14, 18));

    final stops = <double>[];
    for (var i = 0; i < _chakraY.length; i++) {
      stops.add(i / (_chakraY.length - 1));
    }
    final colors = _chakraColors.map((c) => c.withValues(alpha: 0.7 * o));
    final line = _stroke(Colors.white, 2.4);
    line.shader = ui.Gradient.linear(
      Offset(960, _chakraY.first),
      Offset(960, _chakraY.last),
      colors.toList(),
      stops,
    );
    canvas.drawPath(channel, line);

    // Light rising along the channel.
    for (final metric in channel.computeMetrics()) {
      for (var k = 0; k < 3; k++) {
        final f = (t * 0.12 + k / 3) % 1.0;
        final tangent = metric.getTangentForOffset(metric.length * f);
        if (tangent == null) continue;
        final bead = _white(math.sin(f * math.pi) * 0.8 * o);
        canvas.drawCircle(tangent.position, 3.2, _fill(bead, 3));
      }
    }

    for (var i = 0; i < points.length; i++) {
      final at = points[i];
      final color = _chakraColors[i];
      final pulse = 1 + 0.12 * math.sin(t * 1.6 + i * 0.9);
      final halo = color.withValues(alpha: 0.35 * o);
      canvas.drawCircle(at, 18 * pulse, _fill(halo, 6));
      final ring = _stroke(color.withValues(alpha: o), 1.6);
      ring.strokeCap = StrokeCap.butt;
      final ringRect = Rect.fromCircle(center: at, radius: 11);
      final spin = t * (i.isEven ? 0.5 : -0.5);
      for (var d = 0; d < _dashes; d++) {
        final start = spin + d * _dashStep;
        canvas.drawArc(ringRect, start, _dashStep * 0.45, false, ring);
      }
      canvas.drawCircle(at, 4.5, _fill(color.withValues(alpha: o)));
      canvas.drawCircle(at, 1.8, _fill(_white(o)));
    }
  }

  @override
  bool shouldRepaint(NeuraNebulaPainter oldDelegate) {
    final sameTime = oldDelegate.seconds == seconds;
    return !sameTime || oldDelegate.controller != controller;
  }
}

class _Star {
  const _Star({
    required this.at,
    required this.radius,
    required this.opacity,
    required this.phase,
    required this.speed,
    required this.color,
  });

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

  static const Set<NeuraViseme> _rounded = {
    NeuraViseme.O,
    NeuraViseme.U,
    NeuraViseme.WQ,
    NeuraViseme.R,
    NeuraViseme.CHJSH,
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    if (pose.open == 0) {
      _paintRest(canvas);
    } else {
      _paintOpen(canvas);
    }
    canvas.restore();
  }

  void _paintRest(Canvas canvas) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.09
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x73FFFFFF);
    final dip = pose.viseme == NeuraViseme.MBP ? 0.5 : 0.6;
    final curve = Path()
      ..moveTo(0.12, 0.5)
      ..quadraticBezierTo(0.5, dip, 0.88, 0.5);
    canvas.drawPath(curve, line);
  }

  void _paintOpen(Canvas canvas) {
    final rounded = _rounded.contains(pose.viseme);
    final width = rounded ? 0.5 : 0.86;
    final height = (0.12 + pose.open * 0.8).clamp(0.0, 0.95);
    final rect = Rect.fromCenter(
      center: const Offset(0.5, 0.5),
      width: width,
      height: height,
    );
    final glow = Paint()
      ..color = const Color(0x8C9EE7FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08);
    canvas.drawOval(rect.inflate(0.06), glow);
    canvas.drawOval(rect, Paint()..color = const Color(0xD9FFFFFF));
    final inset = math.min(0.06, height * 0.25);
    final core = Paint()..color = const Color(0xFFBFF3FF);
    canvas.drawOval(rect.deflate(inset), core);
  }

  @override
  bool shouldRepaint(NebulaMouthPainter oldDelegate) {
    return oldDelegate.pose != pose;
  }
}
