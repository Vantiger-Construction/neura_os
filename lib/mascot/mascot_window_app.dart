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

class _MascotHomeState extends State<_MascotHome> with WindowListener {
  WindowManagerPlus get _wm => WindowManagerPlus.current;

  @override
  void initState() {
    super.initState();
    _wm.addListener(this);
    _setup();
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
        child: Image.asset(
          'assets/images/neura_fullbody.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Text(
              'NEURA',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }
}
