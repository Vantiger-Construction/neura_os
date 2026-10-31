import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

import '../avatar/motion/neura_animated_body.dart';
import '../avatar/motion/neura_gesture.dart';
import '../avatar/motion/neura_motion_engine.dart';

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

  // Her body in this isolate: the same spring engine the main app uses, fed
  // by MascotEventBridge. Replaces the old fixed sine sway + random "notice".
  final NeuraMotionEngine _body = NeuraMotionEngine()..setFrozen(true);
  bool _bodyActive = false;
  bool _reduceMotion = false;
  bool get _mayAnimate => _bodyActive && !_body.isStill && !_reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_mayAnimate) _stopVisualMotion();
  }

  void _stopVisualMotion() {
    _thinking = _talking = _listening = _error = false;
    _errorTimer?.cancel();
    _pulseController.stop();
    _pulseController.value = 0;
    _entrance.stop();
    _entrance.value = 1;
  }

  final Stopwatch _bodyClock = Stopwatch()..start();
  Duration _bodyLast = Duration.zero;

  NeuraPose _sampleBody() {
    final now = _bodyClock.elapsed;
    final dt = (now - _bodyLast).inMicroseconds / 1e6;
    if (dt < 0.002) return _body.pose;
    _bodyLast = now;
    return _body.tick(dt);
  }

  // One-shot "wakes up" the first time the window appears.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Driven by events forwarded from the main engine via
  // MascotEventBridge/MascotWindowService.sendEvent -- see onEventFromWindow
  // below. Best-effort/visual-only: never treated as authoritative state.
  bool _thinking = false;
  bool _talking = false;
  bool _listening = false;
  bool _error = false;
  Timer? _errorTimer;
  double _mood = 0.0; // -1..1
  double _energy = 0.4; // 0..1

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _wm.addListener(this);
    _setup();
    _entrance.forward().then((_) {
      if (mounted) _body.gesture(NeuraGesture.wave, intensity: 0.6);
    });
  }

  void _syncBodyPhase() {
    _body.setPhase(
      _error
          ? NeuraBodyPhase.error
          : _listening
              ? NeuraBodyPhase.listening
              : _talking
                  ? NeuraBodyPhase.speaking
                  : _thinking
                      ? NeuraBodyPhase.thinking
                      : NeuraBodyPhase.idle,
    );
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    if (eventName != 'neura_state') return null;
    try {
      final args = Map<String, dynamic>.from(arguments as Map);
      if (args['v'] != 1) return null; // unknown payload version, ignore
      final kind = args['kind'] as String?;
      if (kind != 'body' && !_mayAnimate) return null;
      switch (kind) {
        case 'thinking':
          _setThinking(args['on'] as bool? ?? false);
          break;
        case 'talking':
          _setTalking(args['on'] as bool? ?? false);
          break;
        case 'mood':
          if (!mounted) break;
          setState(() {
            _mood = ((args['mood'] as num?) ?? _mood).toDouble().clamp(
                  -1.0,
                  1.0,
                );
            _energy = ((args['energy'] as num?) ?? _energy).toDouble().clamp(
                  0.0,
                  1.0,
                );
          });
          _body.setMood(_mood, _energy);
          break;
        case 'pulse':
          _firePulse();
          if (args['wave'] == true) _body.gesture(NeuraGesture.wave);
          break;
        case 'listening':
          _listening = args['on'] as bool? ?? false;
          _syncBodyPhase();
          break;
        case 'error':
          _error = true;
          _syncBodyPhase();
          _errorTimer?.cancel();
          _errorTimer = Timer(const Duration(seconds: 2), () {
            _error = false;
            _syncBodyPhase();
          });
          break;
        case 'gesture':
          final g = NeuraGesture.fromWire(args['gesture']);
          final k = args['intensity'];
          if (g != null) {
            _body.gesture(
              g,
              intensity: k is num && k.isFinite ? k.toDouble() : 0.7,
            );
          }
          break;
        case 'mouth':
          final open = args['open'];
          if (open is num) _body.setMouthOpen(open.toDouble());
          break;
        case 'body':
          _bodyActive = args['active'] == true && args['safe'] == false;
          _body.setFrozen(!_bodyActive);
          _body.setMotionLevel(switch (args['motion']) {
            'still' => NeuraBodyMotionLevel.still,
            'subtle' => NeuraBodyMotionLevel.subtle,
            'expressive' => NeuraBodyMotionLevel.expressive,
            _ => NeuraBodyMotionLevel.still,
          });
          _body.setStance(
            NeuraBodyStance.values.firstWhere(
              (v) => v.name == args['stance'],
              orElse: () => NeuraBodyStance.welcoming,
            ),
          );
          if (!_mayAnimate) _stopVisualMotion();
          if (mounted) setState(() {});
          break;
      }
    } catch (_) {
      // Malformed/unexpected payload -- ignore, this is a visual hint only.
    }
    return null;
  }

  void _setThinking(bool value) {
    if (!mounted || _thinking == value) return;
    setState(() => _thinking = value);
    _syncBodyPhase();
    if (value) {
      _pulseController.repeat(reverse: true);
    } else if (!_talking) {
      _pulseController.stop();
      _pulseController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  void _setTalking(bool value) {
    if (!mounted || _talking == value) return;
    setState(() => _talking = value);
    _syncBodyPhase();
    if (value) {
      _pulseController.repeat(reverse: true);
    } else if (!_thinking) {
      _pulseController.stop();
      _pulseController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  void _firePulse() {
    if (!mounted) return;
    _pulseController.forward(from: 0).then((_) {
      if (mounted && !_thinking && !_talking) {
        _pulseController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
        );
      }
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
        final saved = prefs.getDouble(_kPosXKey) != null &&
                prefs.getDouble(_kPosYKey) != null
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
    _errorTimer?.cancel();
    _wm.removeListener(this);
    _entrance.dispose();
    _pulseController.dispose();
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

  /// Warm gold for a positive mood, cool blue for a negative one -- purely a
  /// visual hint, not a claim about the user's actual state.
  Color get _glowColor => Color.lerp(
        const Color(0xFF64B5F6),
        const Color(0xFFFFD54F),
        (_mood + 1) / 2,
      )!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _wm.startDragging(),
        onTap: () => _body.gesture(NeuraGesture.bounce, intensity: 0.8),
        child: Padding(
          // Headroom so gestures and breathing never clip against the window
          // edge (the OS window itself doesn't resize).
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 12),
          child: AnimatedBuilder(
            animation: Listenable.merge([_entrance, _pulseController]),
            child: NeuraAnimatedBody(
              sampler: _sampleBody,
              respectAppLifecycle: false,
              animate: _bodyActive && !_body.isStill,
              showAura: false, // the mascot keeps its own mood glow below
              child: RepaintBoundary(child: _buildSprite(context)),
            ),
            builder: (context, body) {
              final entranceT = Curves.easeOutCubic.transform(_entrance.value);
              return Opacity(
                opacity: entranceT,
                child: Transform.translate(
                  offset: Offset(0, (1 - entranceT) * 24),
                  child: Transform.scale(
                    scale: 0.92 + 0.08 * entranceT,
                    child: _buildGlow(body!),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGlow(Widget child) {
    final active = _thinking || _talking || _listening;
    final pt = _pulseController.value;
    final pulseGlowStrength =
        active ? (0.25 + 0.35 * pt) * (0.5 + _energy) : 0.0;
    final idleGlowAlpha = 0.05 + 0.035 * _body.pose.glow;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: idleGlowAlpha),
            blurRadius: 46,
            spreadRadius: 8,
          ),
          if (pulseGlowStrength > 0)
            BoxShadow(
              color: _glowColor.withValues(
                alpha: pulseGlowStrength.clamp(0.0, 1.0),
              ),
              blurRadius: 30 + 20 * pt,
              spreadRadius: 4 + 6 * pt,
            ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSprite(BuildContext context) {
    // Height-only decode preserves the art's aspect ratio.
    return Image.asset(
      'assets/images/neura_fullbody.png',
      fit: BoxFit.contain,
      cacheHeight:
          (_kWindowHeight * MediaQuery.devicePixelRatioOf(context)).round(),
      errorBuilder: (_, __, ___) => const Center(
        child: Text(
          'NEURA',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
