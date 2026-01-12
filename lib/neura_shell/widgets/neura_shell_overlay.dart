import 'package:flutter/material.dart';

import '../neura_shell.dart';
import 'neura_room_backdrop.dart';
import 'neura_room_selector_sheet.dart';
import 'neura_rive_resident.dart';

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
              NeuraRiveResident(
                key: ValueKey('neura_rive_resident_${state.room.id}'),
                room: state.room,
              ),
          ],
        );
      },
    );
  }
}
