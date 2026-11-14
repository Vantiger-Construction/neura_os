import 'package:flutter/material.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

import 'mascot_window_app.dart';

/// Keeps the secondary engine independent of primary app services, including
/// when its optional window plugin is missing or never finishes initializing.
class MascotWindowBootstrap extends StatefulWidget {
  const MascotWindowBootstrap({
    super.key,
    required this.windowId,
    required this.onInitializationError,
    this.initializeWindow = WindowManagerPlus.ensureInitialized,
  });

  final int windowId;
  final void Function(Object, StackTrace) onInitializationError;
  final Future<void> Function(int) initializeWindow;

  @override
  State<MascotWindowBootstrap> createState() => _MascotWindowBootstrapState();
}

class _MascotWindowBootstrapState extends State<MascotWindowBootstrap> {
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await widget
          .initializeWindow(widget.windowId)
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onInitializationError(error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const MascotWindowApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _failed
                  ? 'The floating companion is unavailable.\n'
                      'You can continue in the main Neura window.'
                  : 'Starting the floating companion.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
