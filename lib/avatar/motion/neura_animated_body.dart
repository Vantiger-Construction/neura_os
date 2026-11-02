// lib/avatar/motion/neura_animated_body.dart
//
// Renders any avatar child (full-body art, a Lottie, a sprite) with Neura's
// live procedural pose. The child is rasterised once behind a RepaintBoundary;
// each frame only the composited transform and aura change.
//
// Respects OS reduced-motion and TickerMode (offstage routes don't tick).

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'neura_motion.dart';
import 'neura_motion_engine.dart';

typedef NeuraPoseSampler = NeuraPose Function();

class NeuraAnimatedBody extends StatefulWidget {
  const NeuraAnimatedBody({
    super.key,
    required this.child,
    this.sampler,
    this.animate = true,
    this.respectAppLifecycle = true,
    this.showAura = true,
    this.auraColorCool = const Color(0xFF64B5F6),
    this.auraColorWarm = const Color(0xFFFFD54F),
  });

  final Widget child;

  /// Where the pose comes from. Defaults to the app-wide [NeuraMotion].
  final NeuraPoseSampler? sampler;

  /// Hard off-switch (e.g. Safe Mode surfaces). Renders neutral.
  final bool animate;

  /// Separate mascot engines use an explicit main-window activity signal.
  final bool respectAppLifecycle;

  final bool showAura;
  final Color auraColorCool;
  final Color auraColorWarm;

  @override
  State<NeuraAnimatedBody> createState() => _NeuraAnimatedBodyState();
}

class _NeuraAnimatedBodyState extends State<NeuraAnimatedBody>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<NeuraPose> _pose = ValueNotifier(NeuraPose.neutral);
  bool _reduceMotion = false;
  bool _foreground = true;
  bool _tickerEnabled = true;

  NeuraPoseSampler get _sampler =>
      widget.sampler ?? NeuraMotion.instance.sample;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((_) {
      final p = _sampler();
      if (p.isFinite) _pose.value = p;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.sampler == null) {
      // remove-then-add keeps exactly one registration across rebuilds.
      NeuraMotion.instance.live.removeListener(_sync);
      NeuraMotion.instance.live.addListener(_sync);
    }
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(NeuraAnimatedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sampler != widget.sampler) {
      NeuraMotion.instance.live.removeListener(_sync);
      if (widget.sampler == null) NeuraMotion.instance.live.addListener(_sync);
    }
    _sync();
  }

  bool get _live => widget.sampler != null || NeuraMotion.instance.live.value;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final run = widget.animate &&
        !_reduceMotion &&
        _live &&
        (_foreground || !widget.respectAppLifecycle) &&
        _tickerEnabled;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run) {
      _ticker.stop();
      _pose.value = NeuraPose.neutral;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Mascot isolate passes its own sampler and never touches the app runtime.
    if (widget.sampler == null) {
      NeuraMotion.instance.live.removeListener(_sync);
    }
    _ticker.dispose();
    _pose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = RepaintBoundary(child: widget.child);
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 200.0;
      return ValueListenableBuilder<NeuraPose>(
        valueListenable: _pose,
        child: body,
        builder: (context, p, child) {
          final sx = p.scale * (1 - p.squash * 0.5);
          final sy = p.scale * (1 + p.squash);
          final posed = Transform.translate(
            offset: Offset(p.dx * w, p.dy * h),
            child: Transform.rotate(
              angle: p.lean,
              alignment: Alignment.bottomCenter,
              child: Transform.rotate(
                angle: p.tilt,
                alignment: Alignment.center,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(sx, sy, 1),
                  child: child,
                ),
              ),
            ),
          );
          if (!widget.showAura) return posed;
          final aura = Color.lerp(
            widget.auraColorCool,
            widget.auraColorWarm,
            (p.warmth + 1) / 2,
          )!;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: h * 0.02,
                child: IgnorePointer(
                  child: Container(
                    width: w * 0.55,
                    height: h * 0.06,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(
                        Radius.elliptical(w * 0.3, h * 0.04),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: aura.withValues(
                            alpha: (0.12 + p.glow * 0.45).clamp(0.0, 1.0),
                          ),
                          blurRadius: 18 + 26 * p.glow,
                          spreadRadius: 2 + 8 * p.glow,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              posed,
            ],
          );
        },
      );
    });
  }
}
