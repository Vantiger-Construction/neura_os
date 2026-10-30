import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../avatar/avatar_globals.dart';
import '../../avatar/avatar_registry.dart';
import '../../avatar/avatar_view.dart';
import '../../services/neura_companion_presence.dart';
import '../../src/shell/shell_prefs.dart';
import '../models/neura_room.dart';
import '../models/neura_room_presence_profile.dart';

/// Neura's safe, non-interactive in-room presence.
///
/// This widget never opens a microphone. It only renders the selected avatar
/// and lets the shared NeuraMotion body engine animate it. Safe Mode,
/// reduced-motion accessibility, and the Still preference all freeze motion.
class NeuraRoomPresenceAvatar extends StatefulWidget {
  const NeuraRoomPresenceAvatar({
    super.key,
    required this.room,
    required this.phase,
    required this.motion,
    required this.scale,
    this.compact = false,
  });

  final NeuraRoom room;
  final NeuraPresencePhase phase;
  final NeuraCompanionMotion motion;
  final NeuraCompanionScale scale;
  final bool compact;

  @override
  State<NeuraRoomPresenceAvatar> createState() =>
      _NeuraRoomPresenceAvatarState();
}

class _NeuraRoomPresenceAvatarState extends State<NeuraRoomPresenceAvatar>
    with WidgetsBindingObserver {
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
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
  Widget build(BuildContext context) {
    final profile = NeuraRoomPresenceProfile.forRoom(widget.room);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final selectedId = AvatarGlobals.service.selectedAvatarId;

    Widget avatarFor(String id) => LayoutBuilder(
          builder: (context, constraints) {
            final available =
                math.min(constraints.maxWidth, constraints.maxHeight);
            final compactSize = widget.compact ? 60.0 : 168.0;
            final baseSize =
                available.isFinite && available > 0 ? available : compactSize;
            final size = math
                .max(40.0, baseSize * profile.avatarScale * widget.scale.factor)
                .toDouble();
            final spec = AvatarRegistry.byId(id);
            return Align(
              alignment: profile.alignment,
              child: SizedBox.square(
                dimension: size,
                child: widget.phase == NeuraPresencePhase.safeMode
                    ? Image.asset(
                        'assets/images/neura_fullbody.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.auto_awesome_rounded,
                          size: widget.compact ? 32 : 80,
                          color: accent,
                        ),
                      )
                    : AvatarView(
                        spec: spec,
                        controller: AvatarGlobals.controller,
                        size: size,
                      ),
              ),
            );
          },
        );

    return RepaintBoundary(
        child: TickerMode(
            enabled: _foreground &&
                !reduceMotion &&
                widget.phase != NeuraPresencePhase.safeMode &&
                widget.motion != NeuraCompanionMotion.still,
            child: Semantics(
              image: true,
              label:
                  'Neura in ${widget.room.title}, ${profile.stanceLabel}, ${NeuraPresenceSnapshot(widget.phase).label}',
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.08, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                // Body motion (idle sway, breathing, gestures) comes from the shared
                // NeuraMotion engine inside AvatarView, which already honours Safe
                // Mode, the Still preference and OS reduced-motion.
                child: KeyedSubtree(
                  key: ValueKey<String>(widget.room.id),
                  child: ValueListenableBuilder<String>(
                    valueListenable: selectedId,
                    builder: (_, id, __) => avatarFor(id),
                  ),
                ),
              ),
            )));
  }
}
