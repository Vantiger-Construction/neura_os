import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../neura_shell.dart';
import 'neura_room_backdrop.dart';
import 'neura_room_selector_sheet.dart';

/// Global background + avatar overlay.
///
/// This wraps the Navigator via MaterialApp.builder so it affects all screens.
class NeuraShellOverlay extends StatelessWidget {
  final Widget child;

  const NeuraShellOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final state = NeuraShell.of(context);

    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return Stack(
          children: [
            Positioned.fill(child: NeuraRoomBackdrop(room: state.room)),
            Positioned.fill(
              child: GestureDetector(
                // Quick "tap the sky" shortcut to room selector.
                onLongPress: () => NeuraRoomSelectorSheet.open(context),
                behavior: HitTestBehavior.opaque,
                child: child,
              ),
            ),
            if (state.showAvatar)
              _FloatingNeuraAvatar(
                key: ValueKey('avatar_${state.room.id}'),
              ),
          ],
        );
      },
    );
  }
}

class _FloatingNeuraAvatar extends StatefulWidget {
  const _FloatingNeuraAvatar({super.key});

  @override
  State<_FloatingNeuraAvatar> createState() => _FloatingNeuraAvatarState();
}

class _FloatingNeuraAvatarState extends State<_FloatingNeuraAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Drifty motion without taking over the UI.
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final p = Curves.easeInOut.transform(_t.value);
        final dx = lerpDouble(-6, 8, p)!;
        final dy = lerpDouble(0, 10, sin(_t.value * pi * 2) * 0.5 + 0.5)!;

        return PositionedDirectional(
          end: 10 + dx,
          bottom: 86 + dy,
          child: IgnorePointer(
            ignoring: true,
            child: Opacity(
              opacity: 0.9,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      spreadRadius: 2,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ],
                ),
                child: const _NeuraAvatarFace(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NeuraAvatarFace extends StatelessWidget {
  const _NeuraAvatarFace();

  @override
  Widget build(BuildContext context) {
    // We don't hard-require a Lottie file; use the app's avatar PNG if present.
    // If missing, fall back to a simple glyph.
    return ClipOval(
      child: Image.asset(
        'assets/images/ai_avatar.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            color: Colors.black.withOpacity(0.35),
            alignment: Alignment.center,
            child: Text(
              'N',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          );
        },
      ),
    );
  }
}
