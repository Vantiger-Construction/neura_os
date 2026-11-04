import 'package:flutter/material.dart';

import '../../core/neura_events_extra.dart';
import '../../reliability/safe_boot.dart';
import '../avatar_controller.dart';
import '../avatar_rive_inputs.dart';

/// Content-free rendering contract, independent of any native animation rig.
@immutable
class NeuraMouthPose {
  const NeuraMouthPose._(this.viseme, this.open);

  static const rest = NeuraMouthPose._(NeuraViseme.rest, 0);
  final NeuraViseme viseme;
  final double open;

  factory NeuraMouthPose.fromInputs(double index, double openness) {
    if (!index.isFinite ||
        index != index.truncateToDouble() ||
        index < 0 ||
        index >= NeuraViseme.values.length ||
        !openness.isFinite) {
      return rest;
    }
    final shape = NeuraViseme.values[index.toInt()];
    return NeuraMouthPose._(
      shape,
      shape == NeuraViseme.rest || shape == NeuraViseme.MBP
          ? 0
          : openness.clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NeuraMouthPose && viseme == other.viseme && open == other.open;

  @override
  int get hashCode => Object.hash(viseme, open);
}

/// Composes a mouth over compatible *mouth-free* artwork in the same bounds.
/// [mouthBounds] is normalized to the child's canvas, including its padding.
/// The parent must provide finite width and height (for example SizedBox).
/// No microphone, speech engine, model, frame ticker or network is opened here.
class NeuraMouthLayer extends StatefulWidget {
  NeuraMouthLayer({
    super.key,
    required this.controller,
    required this.child,
    required this.mouthBounds,
    this.enabled = true,
  }) : assert(mouthBounds.left >= 0 &&
            mouthBounds.top >= 0 &&
            mouthBounds.right <= 1 &&
            mouthBounds.bottom <= 1 &&
            mouthBounds.width > 0 &&
            mouthBounds.height > 0);

  final AvatarController controller;
  final Widget child;
  final Rect mouthBounds;
  final bool enabled;

  @override
  State<NeuraMouthLayer> createState() => _NeuraMouthLayerState();
}

class _NeuraMouthLayerState extends State<NeuraMouthLayer>
    with WidgetsBindingObserver {
  NeuraMouthPose _pose = NeuraMouthPose.rest;
  bool _foreground = true;
  bool _tickerEnabled = true;
  bool _reduceMotion = false;
  bool _armed = false;
  late bool _wasTalking;

  bool get _allowed =>
      widget.enabled &&
      _foreground &&
      _tickerEnabled &&
      !_reduceMotion &&
      !SafeBoot.instance.safeMode.value;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _wasTalking = widget.controller.signals.isTalking;
    widget.controller.addListener(_onController);
    SafeBoot.instance.safeMode.addListener(_onBoundary);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _onBoundary();
  }

  @override
  void didUpdateWidget(NeuraMouthLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _wasTalking = widget.controller.signals.isTalking;
      _armed = false;
      _pose = NeuraMouthPose.rest;
    }
    _onBoundary();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _onBoundary();
  }

  void _onBoundary() {
    if (!_allowed) _armed = false;
    _updatePose();
  }

  void _onController() {
    final talking = widget.controller.signals.isTalking;
    if (!_allowed || !talking) {
      _armed = false;
    } else if (!_wasTalking) {
      // Recovery/remount never replays cached inputs from an old utterance.
      _armed = true;
    }
    _wasTalking = talking;
    _updatePose();
  }

  void _updatePose() {
    final next = _allowed && _armed && widget.controller.signals.isTalking
        ? NeuraMouthPose.fromInputs(
            widget.controller.numberInput(AvatarRiveInputs.viseme),
            widget.controller.numberInput(AvatarRiveInputs.mouthOpen),
          )
        : NeuraMouthPose.rest;
    if (next != _pose && mounted) setState(() => _pose = next);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    SafeBoot.instance.safeMode.removeListener(_onBoundary);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final bounds = widget.mouthBounds;
          return Stack(fit: StackFit.expand, children: [
            RepaintBoundary(child: widget.child),
            Positioned(
              left: bounds.left * constraints.maxWidth,
              top: bounds.top * constraints.maxHeight,
              width: bounds.width * constraints.maxWidth,
              height: bounds.height * constraints.maxHeight,
              child: IgnorePointer(
                  child: RepaintBoundary(
                child: CustomPaint(painter: NeuraMouthPainter(_pose)),
              )),
            ),
          ]);
        },
      );
}

/// Drawn only on a changed pose. Closure is immediate, with no tween overshoot.
class NeuraMouthPainter extends CustomPainter {
  const NeuraMouthPainter(this.pose);
  final NeuraMouthPose pose;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final lip = Paint()..color = const Color(0xFF713C65);
    final line = Paint()
      ..color = const Color(0xFF713C65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.055
      ..strokeCap = StrokeCap.round;
    if (pose.open == 0) {
      canvas.drawPath(
          Path()
            ..moveTo(0.08, 0.48)
            ..quadraticBezierTo(
                0.5, pose.viseme == NeuraViseme.MBP ? 0.48 : 0.62, 0.92, 0.48),
          line);
      if (pose.viseme == NeuraViseme.MBP) {
        canvas.drawPath(
            Path()
              ..moveTo(0.23, 0.58)
              ..quadraticBezierTo(0.5, 0.68, 0.77, 0.58),
            line);
      }
    } else {
      final rounded = {
        NeuraViseme.O,
        NeuraViseme.U,
        NeuraViseme.WQ,
        NeuraViseme.R,
        NeuraViseme.CHJSH
      }.contains(pose.viseme);
      final width = rounded ? 0.52 : 0.9;
      final height = (0.08 + pose.open * 0.85).clamp(0.0, 0.95);
      final rect = Rect.fromCenter(
          center: const Offset(0.5, 0.5), width: width, height: height);
      final mouth = Path()..addOval(rect);
      canvas.drawPath(mouth, lip);
      canvas.save();
      canvas.clipPath(mouth);
      canvas.drawOval(
          rect.deflate(0.035), Paint()..color = const Color(0xFF261B35));
      if (!rounded && pose.viseme != NeuraViseme.AI) {
        canvas.drawRect(
            Rect.fromLTWH(rect.left, rect.top + 0.025, rect.width,
                pose.viseme == NeuraViseme.FV ? height * 0.62 : height * 0.26),
            Paint()..color = const Color(0xFFFFF4EB));
      }
      if ({NeuraViseme.TH, NeuraViseme.L, NeuraViseme.AI}
          .contains(pose.viseme)) {
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(0.5, rect.bottom - height * 0.12),
                width: width * 0.55,
                height: height * 0.38),
            Paint()..color = const Color(0xFFDB839E));
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NeuraMouthPainter oldDelegate) => oldDelegate.pose != pose;
}
