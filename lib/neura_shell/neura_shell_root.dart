import 'package:flutter/material.dart';

import 'neura_shell_state.dart';
import 'widgets/neura_shell_overlay.dart';

/// Wraps the entire app with:
/// - a persistent "room" backdrop
/// - optional Neura avatar overlay
/// - optional ambient soundscape
class NeuraShellRoot extends StatefulWidget {
  final Widget child;

  const NeuraShellRoot({super.key, required this.child});

  @override
  State<NeuraShellRoot> createState() => _NeuraShellRootState();
}

class _NeuraShellRootState extends State<NeuraShellRoot> {
  final NeuraShellState _state = NeuraShellState();

  @override
  void initState() {
    super.initState();
    // Non-blocking init: show UI immediately, then hydrate.
    _state.load();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NeuraShellScope(
      notifier: _state,
      child: NeuraShellOverlay(child: widget.child),
    );
  }
}
