import 'package:flutter/material.dart';

import 'neura_startup_turntable.dart';

/// Locally rendered artwork with one upright turn and a small breathing motion.
/// No avatar, audio, AI or runtime 3D service is initialized by this widget.
class NeuraStartupAvatar extends StatefulWidget {
  const NeuraStartupAvatar({
    super.key,
    this.animate = true,
    this.turnOnEntry = false,
    this.width = 180,
    this.height = 180,
  })  : assert(width > 0),
        assert(height > 0);

  final bool animate;

  /// Turn once around the vertical axis during the first active animation.
  final bool turnOnEntry;
  final double width;
  final double height;

  @override
  State<NeuraStartupAvatar> createState() => _NeuraStartupAvatarState();
}

class _NeuraStartupAvatarState extends State<NeuraStartupAvatar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _breath;
  bool _foreground = true;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  bool _firstRun = true;
  bool _turntableReady = false;
  Duration? _turnStartedAt;
  final ValueNotifier<int> _turnFrame = ValueNotifier(0);

  static const _turnDuration = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..addListener(_updateTurnFrame);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncMotion();
  }

  @override
  void didUpdateWidget(NeuraStartupAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate ||
        oldWidget.turnOnEntry != widget.turnOnEntry) {
      _syncMotion();
      _updateTurnFrame();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.animate && _foreground && !_reduceMotion && _tickerEnabled) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      if (_breath.isAnimating) _firstRun = false;
      _breath
        ..stop()
        ..value = 0;
      _turnFrame.value = 0;
    }
  }

  void _onTurntableReady(bool ready) {
    _turntableReady = ready;
    // Decode time never consumes the turn or delays startup navigation.
    if (ready && _firstRun && _breath.isAnimating) {
      _turnStartedAt ??= _breath.lastElapsedDuration ?? Duration.zero;
    }
  }

  void _updateTurnFrame() {
    final elapsed = _breath.lastElapsedDuration ?? Duration.zero;
    final started = _turnStartedAt;
    if (!widget.turnOnEntry ||
        !_firstRun ||
        !_turntableReady ||
        !_breath.isAnimating ||
        started == null) {
      _turnFrame.value = 0;
      return;
    }
    final turnElapsed = elapsed - started;
    if (turnElapsed >= _turnDuration) {
      _firstRun = false;
      _turnFrame.value = 0;
      return;
    }
    final progress = (turnElapsed.inMicroseconds / _turnDuration.inMicroseconds)
        .clamp(0.0, 1.0)
        .toDouble();
    _turnFrame.value =
        (Curves.easeInOut.transform(progress) * kNeuraStartupTurntableFrames)
                .round() %
            kNeuraStartupTurntableFrames;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _breath.removeListener(_updateTurnFrame);
    _breath.dispose();
    _turnFrame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Neura starting up',
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned(
              bottom: 14,
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x2222D3EE),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x3322D3EE),
                        blurRadius: 24,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: SizedBox(width: 104, height: 20),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _breath,
              builder: (context, child) {
                final breath = Curves.easeInOutSine.transform(_breath.value);
                final scale = 1 + 0.018 * breath;
                return Transform.translate(
                  offset: Offset(0, -5 * breath),
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                );
              },
              child: RepaintBoundary(
                child: NeuraStartupPortrait(
                  frame: _turnFrame,
                  loadTurntable: widget.turnOnEntry &&
                      widget.animate &&
                      !_reduceMotion &&
                      _tickerEnabled &&
                      _foreground &&
                      _firstRun,
                  onTurntableReady: _onTurntableReady,
                  width: widget.width,
                  height: widget.height,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
