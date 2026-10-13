import 'package:flutter/material.dart';

/// Local artwork with a small breathing motion; no avatar, audio or AI service
/// is initialized by this widget. The decoded image is kept outside the ticker's
/// builder, and only its composited transform changes on animation frames.
class NeuraStartupAvatar extends StatefulWidget {
  const NeuraStartupAvatar({
    super.key,
    this.animate = true,
    this.width = 180,
    this.height = 180,
  })  : assert(width > 0),
        assert(height > 0);

  final bool animate;
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

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
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
    if (oldWidget.animate != widget.animate) _syncMotion();
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
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bound decode size instead of retaining a full 1100 x 1500 RGBA texture
    // for a small splash image. Rebuilds reuse Flutter's image cache entry.
    final decodeHeight =
        (widget.height * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(1, 1024)
            .toInt();
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
                return Transform.translate(
                  offset: Offset(0, -5 * breath),
                  child: Transform.scale(
                    scale: 1 + 0.018 * breath,
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                );
              },
              child: RepaintBoundary(
                child: Image.asset(
                  'assets/images/neura_fullbody.png',
                  bundle: DefaultAssetBundle.of(context),
                  width: widget.width,
                  height: widget.height,
                  fit: BoxFit.contain,
                  cacheHeight: decodeHeight,
                  filterQuality: FilterQuality.low,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.face_rounded,
                    size: 72,
                    color: Color(0xFFC4B5FD),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
