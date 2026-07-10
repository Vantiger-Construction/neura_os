import 'package:flutter/material.dart';

import '../neura_shell.dart';
import 'neura_room_backdrop.dart';
import 'neura_room_selector_sheet.dart';

/// Global background overlay.
///
/// The avatar previously overlaid here (NeuraRiveResident) now lives in its
/// own floating always-on-top OS window instead — see
/// lib/mascot/mascot_window_app.dart and NeuraShellState's showAvatar wiring.
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
          ],
        );
      },
    );
  }
}
