import 'package:flutter/material.dart';

import '../avatar_controller.dart';
import 'neura_mouth_layer.dart';

/// Built-in, mouth-free vector portrait with event-driven speech articulation.
/// It is independently selectable; it does not deform the painted body PNG.
class FlutterMouthAvatarView extends StatelessWidget {
  const FlutterMouthAvatarView({
    super.key,
    required this.controller,
    this.size = 128,
    this.enabled = true,
  });
  final AvatarController controller;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'Neura expressive face',
        child: SizedBox.square(
            dimension: size,
            child: NeuraMouthLayer(
              controller: controller,
              enabled: enabled,
              mouthBounds: const Rect.fromLTWH(0.37, 0.56, 0.26, 0.14),
              child: const CustomPaint(painter: _ExpressiveFacePainter()),
            )),
      );
}

class _ExpressiveFacePainter extends CustomPainter {
  const _ExpressiveFacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    final paint = Paint();
    canvas.drawCircle(
        const Offset(100, 94), 90, paint..color = const Color(0xFF221F3D));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(32, 21, 136, 159), const Radius.circular(65)),
        paint..color = const Color(0xFF8665BD));
    canvas.drawOval(const Rect.fromLTWH(49, 36, 102, 119),
        paint..color = const Color(0xFFF2D3CB));
    canvas.drawPath(
        Path()
          ..moveTo(40, 78)
          ..quadraticBezierTo(44, 6, 112, 25)
          ..quadraticBezierTo(166, 20, 160, 90)
          ..quadraticBezierTo(129, 69, 108, 45)
          ..quadraticBezierTo(78, 77, 40, 78),
        paint..color = const Color(0xFFAE85E4));
    for (final x in [78.0, 122.0]) {
      canvas.drawOval(
          Rect.fromCenter(center: Offset(x, 91), width: 23, height: 13),
          paint..color = const Color(0xFFFFFCFA));
      canvas.drawCircle(
          Offset(x, 91), 6, paint..color = const Color(0xFF39888E));
      canvas.drawCircle(
          Offset(x, 91), 3, paint..color = const Color(0xFF24213B));
      canvas.drawCircle(Offset(x - 2, 89), 1.7, paint..color = Colors.white);
    }
    canvas.drawPath(
        Path()
          ..moveTo(100, 99)
          ..lineTo(96, 111)
          ..lineTo(102, 112),
        Paint()
          ..color = const Color(0xFFC68C8C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round);
    canvas.drawPath(
        Path()
          ..moveTo(37, 194)
          ..quadraticBezierTo(40, 154, 77, 151)
          ..quadraticBezierTo(100, 173, 123, 151)
          ..quadraticBezierTo(160, 154, 163, 194)
          ..close(),
        paint..color = const Color(0xFFC4ECEE));
    canvas.drawPath(
        Path()
          ..moveTo(100, 184)
          ..cubicTo(77, 170, 93, 161, 100, 171)
          ..cubicTo(107, 161, 123, 170, 100, 184),
        paint..color = const Color(0xFF9263C4));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ExpressiveFacePainter oldDelegate) => false;
}
