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
    with WindowListener, SingleTickerProviderStateMixin {
  WindowManagerPlus get _wm => WindowManagerPlus.current;

  // Driven by events forwarded from the main engine via
  // MascotEventBridge/MascotWindowService.sendEvent -- see onEventFromWindow
  // below. Best-effort/visual-only: never treated as authoritative state.
  bool _thinking = false;
  bool _talking = false;
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
  }

  @override
  Future<dynamic> onEventFromWindow(
      String eventName, int fromWindowId, dynamic arguments) async {
    if (eventName != 'neura_state') return null;
    try {
      final args = Map<String, dynamic>.from(arguments as Map);
      if (args['v'] != 1) return null; // unknown payload version, ignore
      final kind = args['kind'] as String?;
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
            _mood = ((args['mood'] as num?) ?? _mood).toDouble().clamp(-1.0, 1.0);
            _energy = ((args['energy'] as num?) ?? _energy).toDouble().clamp(0.0, 1.0);
          });
          break;
        case 'pulse':
          _firePulse();
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
    if (value) {
      _pulseController.repeat(reverse: true);
    } else if (!_talking) {
      _pulseController.stop();
      _pulseController.animateTo(0, duration: const Duration(milliseconds: 300));
    }
  }

  void _setTalking(bool value) {
    if (!mounted || _talking == value) return;
    setState(() => _talking = value);
    if (value) {
      _pulseController.repeat(reverse: true);
    } else if (!_thinking) {
      _pulseController.stop();
      _pulseController.animateTo(0, duration: const Duration(milliseconds: 300));
    }
  }

  void _firePulse() {
    if (!mounted) return;
    _pulseController.forward(from: 0).then((_) {
      if (mounted && !_thinking && !_talking) {
        _pulseController.animateTo(0, duration: const Duration(milliseconds: 300));
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
    _wm.removeListener(this);
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
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final active = _thinking || _talking;
            final t = _pulseController.value;
            final glowStrength = active ? (0.25 + 0.35 * t) * (0.5 + _energy) : 0.0;
            return DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: glowStrength <= 0
                    ? const []
                    : [
                        BoxShadow(
                          color: _glowColor.withValues(alpha: glowStrength.clamp(0.0, 1.0)),
                          blurRadius: 30 + 20 * t,
                          spreadRadius: 4 + 6 * t,
                        ),
                      ],
              ),
              child: child,
            );
          },
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
        ),
      ),
    );
  }
}
