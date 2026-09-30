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
/// and applies subtle motion from already-public presence state. Safe Mode,
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  bool get _mayAnimate =>
      widget.phase != NeuraPresencePhase.safeMode &&
      widget.motion != NeuraCompanionMotion.still;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _syncMotion();
  }

  @override
  void didUpdateWidget(NeuraRoomPresenceAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase || oldWidget.motion != widget.motion) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    if (_mayAnimate) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = NeuraRoomPresenceProfile.forRoom(widget.room);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animate = _mayAnimate && !reduceMotion;
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

    return Semantics(
      image: true,
      label: 'Neura in ${widget.room.title}, ${profile.stanceLabel}',
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
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
        child: AnimatedBuilder(
          key: ValueKey<String>(widget.room.id),
          animation: _motion,
          builder: (context, child) {
            if (!animate) return child!;
            final wave = math.sin(_motion.value * math.pi * 2);
            final strength =
                widget.motion == NeuraCompanionMotion.expressive ? 1.7 : 1.0;
            final phaseStrength = switch (widget.phase) {
              NeuraPresencePhase.listening => 1.4,
              NeuraPresencePhase.speaking => 1.25,
              NeuraPresencePhase.thinking => 0.8,
              _ => 0.55,
            };
            final translateY = -wave.abs() * 2 * strength * phaseStrength;
            final rotate = widget.phase == NeuraPresencePhase.thinking
                ? wave * 0.012 * strength
                : 0.0;
            final pulse = widget.phase == NeuraPresencePhase.speaking
                ? 1 + wave.abs() * 0.012 * strength
                : 1.0;
            return Transform.translate(
              offset: Offset(0, translateY),
              child: Transform.rotate(
                angle: rotate,
                child: Transform.scale(scale: pulse, child: child),
              ),
            );
          },
          child: ValueListenableBuilder<String>(
            valueListenable: selectedId,
            builder: (_, id, __) => avatarFor(id),
          ),
        ),
      ),
    );
  }
}
