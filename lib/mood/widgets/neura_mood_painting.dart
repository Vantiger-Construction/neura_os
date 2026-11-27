import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../modules/mood/mood_models.dart';

/// One week of check-ins turned into a small abstract painting.
///
/// - The background is the week's average mood: deep indigo for hard weeks,
///   soft teal and lavender in between, warm gold and coral for good ones.
/// - Each check-in is a brushstroke: placed by weekday (left to right) and
///   mood (higher is brighter and higher up), as thick as the energy that
///   day, and as long and flowing as the sleep before it.
///
/// Deterministic: the same week always paints the same picture.
class NeuraMoodPainting extends CustomPainter {
  NeuraMoodPainting({required this.weekStart, required List<MoodEntry> entries})
      : entries = List.unmodifiable(entries
            .where((e) =>
                !e.timestamp.isBefore(weekStart) &&
                e.timestamp.isBefore(weekStart.add(const Duration(days: 7))))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));

  /// Midnight on the Monday that starts the week.
  final DateTime weekStart;
  final List<MoodEntry> entries;

  /// Monday 00:00 of the week containing [time].
  static DateTime weekOf(DateTime time) {
    final day = DateTime(time.year, time.month, time.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static Color moodColor(double mood) {
    const stops = <Color>[
      Color(0xFF283593), // 0: indigo
      Color(0xFF5C6BC0), // 2.5: soft blue
      Color(0xFF4DB6AC), // 5: teal
      Color(0xFFB39DDB), // 6.5: lavender
      Color(0xFFFFB74D), // 8: warm gold
      Color(0xFFFF8A65), // 10: coral
    ];
    const at = <double>[0, 2.5, 5, 6.5, 8, 10];
    final m = mood.clamp(0.0, 10.0);
    for (var i = 1; i < at.length; i++) {
      if (m <= at[i]) {
        final t = (m - at[i - 1]) / (at[i] - at[i - 1]);
        return Color.lerp(stops[i - 1], stops[i], t)!;
      }
    }
    return stops.last;
  }

  double get averageMood => entries.isEmpty
      ? 5
      : entries.map((e) => e.mood0to10).reduce((a, b) => a + b) /
          entries.length;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final base = moodColor(averageMood);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, Colors.black, 0.55)!,
            Color.lerp(base, Colors.black, 0.25)!,
          ],
        ).createShader(rect),
    );
    final rnd = math.Random(weekStart.millisecondsSinceEpoch ~/ 86400000);
    // A soft wash of texture first.
    for (var i = 0; i < 40; i++) {
      final center = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      canvas.drawCircle(
        center,
        size.shortestSide * (0.05 + rnd.nextDouble() * 0.15),
        Paint()..color = base.withValues(alpha: 0.05 + rnd.nextDouble() * 0.06),
      );
    }
    for (final entry in entries) {
      final dayOffset =
          entry.timestamp.difference(weekStart).inMinutes / (7 * 24 * 60);
      final x = size.width * (0.08 + 0.84 * dayOffset);
      final y = size.height * (0.85 - 0.7 * entry.mood0to10 / 10);
      final energy = (entry.energy0to10 ?? 5) / 10;
      final sleep = (entry.sleepHours ?? 7).clamp(0.0, 12.0) / 12;
      final color = moodColor(entry.mood0to10.toDouble());
      final length = size.width * (0.08 + 0.18 * sleep);
      final angle = (rnd.nextDouble() - 0.5) * math.pi * 0.6;
      final start = Offset(
        x - math.cos(angle) * length / 2,
        y - math.sin(angle) * length / 2,
      );
      final end = Offset(
        x + math.cos(angle) * length / 2,
        y + math.sin(angle) * length / 2,
      );
      final bend = (rnd.nextDouble() - 0.5) * size.height * 0.2 * (1 + sleep);
      final control = Offset(x, y + bend);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      final width = size.shortestSide * (0.02 + 0.07 * energy);
      // A blurred halo, then the stroke itself.
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * 2.2
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.8),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NeuraMoodPainting oldDelegate) =>
      oldDelegate.weekStart != weekStart ||
      oldDelegate.entries.length != entries.length;
}
