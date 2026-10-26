import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/neura_companion_presence.dart';

/// Reflects existing activity leases; it never starts audio or inference.
class NeuraActivityBadge extends StatefulWidget {
  const NeuraActivityBadge({super.key, this.offline = false, this.state});
  final bool offline;
  final ValueListenable<NeuraPresenceSnapshot>? state;

  @override
  State<NeuraActivityBadge> createState() => _NeuraActivityBadgeState();
}

class _NeuraActivityBadgeState extends State<NeuraActivityBadge>
    with WidgetsBindingObserver {
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<NeuraPresenceSnapshot>(
        valueListenable: widget.state ?? NeuraCompanionPresence.instance.state,
        builder: (context, snapshot, _) {
          final phase = snapshot.phase;
          final label = snapshot.isSafeMode
              ? snapshot.label
              : !_foreground
                  ? 'Paused · app in background'
                  : phase == NeuraPresencePhase.idle && widget.offline
                      ? 'Ready offline'
                      : phase == NeuraPresencePhase.thinking
                          ? (widget.offline
                              ? 'Thinking offline'
                              : 'Preparing a reply')
                          : snapshot.label;
          final icon = snapshot.isSafeMode
              ? Icons.health_and_safety_outlined
              : !_foreground
                  ? Icons.pause_circle_outline
                  : switch (phase) {
                      NeuraPresencePhase.listening => Icons.mic_none,
                      NeuraPresencePhase.speaking => Icons.volume_up_outlined,
                      NeuraPresencePhase.thinking => Icons.more_horiz,
                      _ => widget.offline
                          ? Icons.computer
                          : Icons.chat_bubble_outline,
                    };
          return Semantics(
            label: label,
            child: Chip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      );
}
