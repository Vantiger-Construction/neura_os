import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

const double _kWindowWidth = 200;
const double _kWindowHeight = 400;
const double _kRightMargin = 24;
const String _kPosXKey = 'neura.mascot.window.x';
const String _kPosYKey = 'neura.mascot.window.y';

/// Widget tree run inside the floating avatar's own Flutter engine/isolate
/// (spawned via [MascotWindowService]). Frameless, always-on-top, draggable,
/// remembers where the user last dragged it.
class MascotWindowApp extends StatelessWidget {
  const MascotWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _MascotHome(),
    );
  }
}

class _MascotHome extends StatefulWidget {
  const _MascotHome();

  @override
  State<_MascotHome> createState() => _MascotHomeState();
}

class _MascotHomeState extends State<_MascotHome>
    with WindowListener, TickerProviderStateMixin {
  WindowManagerPlus get _wm => WindowManagerPlus.current;
  final _rand = math.Random();

  // Continuous idle cycle: breathing, sway and bob are all derived from this
  // single phase so they never need separate controllers.
  late final AnimationController _life =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))
        ..repeat();

  // One-shot "wakes up" the first time the window appears.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // One-shot "notices you" bounce, replayed on a random idle cadence and on tap.
  late final AnimationController _notice = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  Timer? _idleGestureTimer;

  @override
  void initState() {
    super.initState();
    _wm.addListener(this);
    _setup();
    _entrance.forward();
    _scheduleIdleGesture();
  }

  void _scheduleIdleGesture() {
    _idleGestureTimer = Timer(Duration(seconds: 7 + _rand.nextInt(9)), () {
      if (!mounted) return;
      _playNotice();
      _scheduleIdleGesture();
    });
  }

  void _playNotice() {
    _notice.forward(from: 0).then((_) {
      if (mounted) _notice.reverse();
    });
  }

  Future<void> _setup() async {
    await _wm.setAsFrameless();
    await _wm.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(_kWindowWidth, _kWindowHeight),
        alwaysOnTop: true,
        skipTaskbar: true,
        // A fully transparent layered window couldn't be conclusively
        // verified on this rendering pipeline (GDI capture tools can't see
        // into DirectComposition-backed layered surfaces either way, so its
        // true visual state is unknown, not confirmed broken) — a solid
        // backdrop is the proven-working choice. Revisit if a true cutout
        // look is wanted later.
        backgroundColor: Color(0xFF0D0D14),
      ),
      () async {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getDouble(_kPosXKey) != null && prefs.getDouble(_kPosYKey) != null
            ? Offset(prefs.getDouble(_kPosXKey)!, prefs.getDouble(_kPosYKey)!)
            : await _defaultPosition();
        await _wm.setPosition(saved);
        await _wm.setResizable(false);
        await _wm.show(inactive: true);
      },
    );
  }

  /// Right side, vertically centered — out of the way of the app's own UI.
  /// Uses the primary display's actual bounds (not this window's own view,
  /// which by this point has already been resized down to the mascot size).
  Future<Offset> _defaultPosition() async {
    final display = await ScreenRetriever.instance.getPrimaryDisplay();
    final origin = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    final left = origin.dx + size.width - _kWindowWidth - _kRightMargin;
    final top = origin.dy + (size.height - _kWindowHeight) / 2;
    return Offset(left, top);
  }

  @override
  void dispose() {
    _idleGestureTimer?.cancel();
    _wm.removeListener(this);
    _life.dispose();
    _entrance.dispose();
    _notice.dispose();
    super.dispose();
  }

  @override
  void onWindowMoved([int? windowId]) {
    _savePosition();
  }

  Future<void> _savePosition() async {
    final pos = await _wm.getPosition();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPosXKey, pos.dx);
    await prefs.setDouble(_kPosYKey, pos.dy);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _wm.startDragging(),
        onTap: _playNotice,
        child: Padding(
          // Headroom so the breathing/notice scale-up never clips against
          // the window edge (the OS window itself doesn't resize).
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 12),
          child: AnimatedBuilder(
            animation: Listenable.merge([_life, _entrance, _notice]),
            builder: (context, _) {
              final t = _life.value * 2 * math.pi;
              final breathe = 1.0 + 0.02 * math.sin(t);
              // Different frequency multipliers per axis so the motion
              // doesn't repeat in lockstep and reads as organic, not robotic.
              final swayDeg = 1.4 * math.sin(t * 0.5 + 1.0);
              final bobY = 3.5 * math.sin(t * 0.7);
              final glowAlpha = 0.05 + 0.035 * (0.5 + 0.5 * math.sin(t * 0.9));

              final noticeT = Curves.easeOutBack.transform(_notice.value);
              final noticeScale = 1.0 + 0.1 * math.sin(noticeT * math.pi);
              final noticeTiltDeg = 6.0 * math.sin(noticeT * math.pi);

              final entranceT = Curves.easeOutCubic.transform(_entrance.value);

              return Opacity(
                opacity: entranceT,
                child: Transform.translate(
                  offset: Offset(0, bobY + (1 - entranceT) * 24),
                  child: Transform.rotate(
                    angle: (swayDeg + noticeTiltDeg) * math.pi / 180,
                    child: Transform.scale(
                      scale: breathe * noticeScale * (0.92 + 0.08 * entranceT),
                      child: _buildBody(context, glowAlpha),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, double glowAlpha) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: glowAlpha),
            blurRadius: 46,
            spreadRadius: 8,
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/neura_fullbody.png',
        fit: BoxFit.contain,
        cacheWidth: (_kWindowWidth * MediaQuery.devicePixelRatioOf(context)).round(),
        cacheHeight: (_kWindowHeight * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, __, ___) => const Center(
          child: Text(
            'NEURA',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}
